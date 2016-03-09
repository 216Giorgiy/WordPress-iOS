import UIKit
import Social
import WordPressComKit


class ShareViewController: SLComposeServiceViewController {
    private var oauth2Token: NSString?
    private var selectedSiteID: Int?
    private var selectedSiteName: String?
    private var postStatus = "publish"
    
    override func viewDidLoad() {
        let authDetails = ShareExtensionService.retrieveShareExtensionConfiguration()
        oauth2Token = authDetails?.oauth2Token
        selectedSiteID = authDetails?.defaultSiteID
        selectedSiteName = authDetails?.defaultSiteName
    }
    
    // MARK: - UIViewController Methods
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        dismissIfNeeded()
    }
    
    // MARK: - Private Helpers
    private func dismissIfNeeded() {
        guard oauth2Token == nil else {
            return
        }
        
        let title = NSLocalizedString("No WordPress.com Account", comment: "Extension Missing Token Alert Title")
        let message = NSLocalizedString("Launch the WordPress app and sign into your WordPress.com or Jetpack site to share.", comment: "Extension Missing Token Alert Title")
        let accept = NSLocalizedString("Cancel Share", comment: "Dismiss Extension and cancel Share OP")
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .Alert)
        let alertAction = UIAlertAction(title: accept, style: .Default) { (action: UIAlertAction) -> Void in
            self.cancel()
        }
        
        alertController.addAction(alertAction)
        presentViewController(alertController, animated: true, completion: nil)
    }

    override func isContentValid() -> Bool {
        // Do validation of contentText and/or NSExtensionContext attachments here
        return true
    }

    override func didSelectPost() {
        RequestRouter.bearerToken = oauth2Token! as String

        loadWebsiteUrl { (url: NSURL?) in
            let configuration = NSURLSessionConfiguration.backgroundSessionConfigurationWithIdentifier(WPAppGroupName)
            configuration.sharedContainerIdentifier = WPAppGroupName
            let service = PostService(configuration: configuration)
            let (subject, body) = self.splitContentTextIntoSubjectAndBody(self.contentWithSourceURL(url))
            service.createPost(siteID: self.selectedSiteID!, status:self.postStatus, title: subject, body: body) { (post, error) in
                print("Post \(post) Error \(error)")
            }
            
            self.extensionContext!.completeRequestReturningItems([], completionHandler: nil)
        }
    }

    override func configurationItems() -> [AnyObject]! {
        let blogPickerItem = SLComposeSheetConfigurationItem()
        blogPickerItem.title = NSLocalizedString("Post to:", comment: "Upload post to the selected Site")
        blogPickerItem.value = selectedSiteName ?? NSLocalizedString("Select a site", comment: "Select a site in the share extension")
        blogPickerItem.tapHandler = { [weak self] in
            self?.displaySitePicker()
        }
        
        let statusPickerItem = SLComposeSheetConfigurationItem()
        statusPickerItem.title = NSLocalizedString("Post Status:", comment: "Post status picker title in Share Extension")
        statusPickerItem.value = self.postStatuses[postStatus]!
        statusPickerItem.tapHandler = { [weak self] in
            self?.displayStatusPicker()
        }
        
        return [blogPickerItem, statusPickerItem]
    }

    
    private func displaySitePicker() {
        let pickerViewController = SitePickerViewController()
        pickerViewController.onChange = { (siteId, description) in
            self.selectedSiteID = siteId
            self.selectedSiteName = description
            self.reloadConfigurationItems()
        }
        
        pushConfigurationViewController(pickerViewController)
    }
    
    private func displayStatusPicker() {
        let pickerViewController = PostStatusPickerViewController()
        pickerViewController.statuses = postStatuses
        pickerViewController.onChange = { (status, description) in
            self.postStatus = status
            self.reloadConfigurationItems()
        }
        
        pushConfigurationViewController(pickerViewController)
    }
    
    
    // TODO: This should eventually be moved into WordPressComKit
    private let postStatuses = [
        "draft" : NSLocalizedString("Draft", comment: "Draft post status"),
        "publish" : NSLocalizedString("Publish", comment: "Publish post status")]

    private func splitContentTextIntoSubjectAndBody(contentText: String) -> (subject: String, body: String) {
        let fullText = contentText
        let firstCarriageReturnIndex = fullText.rangeOfCharacterFromSet(NSCharacterSet.newlineCharacterSet())
        let firstLineOfText = firstCarriageReturnIndex != nil ? fullText.substringToIndex(firstCarriageReturnIndex!.startIndex) : fullText
        let restOfText = firstCarriageReturnIndex != nil ? fullText.substringFromIndex(firstCarriageReturnIndex!.endIndex) : ""

        return (firstLineOfText, restOfText)
    }
    
    private func contentWithSourceURL(url: NSURL?) -> String {
        guard let url = url else {
            return contentText
        }
        
        // Append the URL to the content itself
        return contentText + "\n\n<a href=\"\(url.absoluteString)\">\(url.absoluteString)</a>"
    }
    
    private func loadWebsiteUrl(completion: (NSURL? -> Void)) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let itemProviders = item.attachments as? [NSItemProvider] else
        {
            completion(nil)
            return
        }
        
        let urlItemProviders = itemProviders.filter({ (itemProvider) -> Bool in
            return itemProvider.hasItemConformingToTypeIdentifier("public.url")
        })
        
        guard urlItemProviders.count > 0 else {
            completion(nil)
            return
        }
        
        itemProviders.first!.loadItemForTypeIdentifier("public.url", options: nil) { (url, error) -> Void in
            guard let theURL = url as? NSURL else {
                completion(nil)
                return
            }
            
            completion(theURL)
        }
    }
}
