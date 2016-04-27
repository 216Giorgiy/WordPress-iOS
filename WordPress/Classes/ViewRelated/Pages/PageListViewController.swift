import Foundation
import WordPressComAnalytics

@objc class PageListViewController : AbstractPostListViewController, PageListTableViewCellDelegate, UIViewControllerRestoration {
    
    private static let pageSectionHeaderHeight = CGFloat(24.0)
    private static let pageCellEstimatedRowHeight = CGFloat(44.0)
    private static let pagesViewControllerRestorationKey = "PagesViewControllerRestorationKey"
    private static let pageCellIdentifier = "PageCellIdentifier"
    private static let pageCellNibName = "PageListTableViewCell"
    private static let restorePageCellIdentifier = "RestorePageCellIdentifier"
    private static let restorePageCellNibName = "RestorePageTableViewCell"
    private static let currentPageListStatusFilterKey = "CurrentPageListStatusFilterKey"
    
    private var cellForLayout : PageListTableViewCell!
    
    
    // MARK: - Convenience constructors
    
    class func controllerWithBlog(blog: Blog) -> PageListViewController {
        
        let storyBoard = UIStoryboard(name: "Pages", bundle: NSBundle.mainBundle())
        let controller = storyBoard.instantiateViewControllerWithIdentifier("PageListViewController") as! PageListViewController
        
        controller.blog = blog
        controller.restorationClass = self
        
        return controller
    }
    
    // MARK: - UIViewControllerRestoration
    
    class func viewControllerWithRestorationIdentifierPath(identifierComponents: [AnyObject], coder: NSCoder) -> UIViewController? {
        
        let context = ContextManager.sharedInstance().mainContext
        
        guard let blogID = coder.decodeObjectForKey(pagesViewControllerRestorationKey) as? String,
            let objectURL = NSURL(string: blogID),
            let objectID = context.persistentStoreCoordinator?.managedObjectIDForURIRepresentation(objectURL),
            let restoredBlog = try? context.existingObjectWithID(objectID) as! Blog else {
                
                return nil
        }
        
        return self.controllerWithBlog(restoredBlog)
    }
    
    // MARK: - UIStateRestoring
    
    override func encodeRestorableStateWithCoder(coder: NSCoder) {
        
        let objectString = blog?.objectID.URIRepresentation().absoluteString
        
        coder.encodeObject(objectString, forKey:self.dynamicType.pagesViewControllerRestorationKey)
        
        super.encodeRestorableStateWithCoder(coder)
    }
    
    // MARK: - UIViewController
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        super.postListViewController = (segue.destinationViewController as! UITableViewController)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = NSLocalizedString("Pages", comment: "Tile of the screen showing the list of pages for a blog.")
    }
    
    // MARK: - Configuration
    
    func configureCellsForLayout() {
        
        let bundle = NSBundle.mainBundle()
        
        cellForLayout = bundle.loadNibNamed(self.dynamicType.pageCellNibName, owner: nil, options: nil)[0] as! PageListTableViewCell
    }
    
    func configureTableView() {
        
        guard let tableView = tableView else {
            return
        }
        
        tableView.accessibilityIdentifier = "PagesTable"
        tableView.isAccessibilityElement = true
        tableView.separatorStyle = .None
        
        let bundle = NSBundle.mainBundle()
        
        // Register the cells
        let pageCellNib = UINib(nibName: self.dynamicType.pageCellNibName, bundle: bundle)
        tableView.registerNib(pageCellNib, forCellReuseIdentifier: self.dynamicType.pageCellIdentifier)
        
        let restorePageCellNib = UINib(nibName: self.dynamicType.restorePageCellNibName, bundle: bundle)
        tableView.registerNib(restorePageCellNib, forCellReuseIdentifier: self.dynamicType.restorePageCellIdentifier)
    }
    
    func noResultsTitleText() -> String {
        if syncHelper?.isSyncing == true {
            return NSLocalizedString("Fetching pages...", comment: "A brief prompt shown when the reader is empty, letting the user know the app is currently fetching new pages.")
        }
        
        if let filter = currentPostListFilter() {
            let titles = noResultsTitles()
            let title = titles[filter.filterType]
            return title ?? ""
        } else {
            return ""
        }
    }
    
    private func noResultsTitles() -> [PostListStatusFilter:String] {
        if isSearching() {
            return noResultsTitlesWhenSearching()
        } else {
            return noResultsTitlesWhenFiltering()
        }
    }
    
    private func noResultsTitlesWhenSearching() -> [PostListStatusFilter:String] {
        
        let draftMessage = String(format: NSLocalizedString("No drafts match your search for %@", comment: "The '%@' is a placeholder for the search term."), currentSearchTerm()!)
        let scheduledMessage = String(format: NSLocalizedString("No scheduled pages match your search for %@", comment: "The '%@' is a placeholder for the search term."), currentSearchTerm()!)
        let trashedMessage = String(format: NSLocalizedString("No trashed pages match your search for %@", comment: "The '%@' is a placeholder for the search term."), currentSearchTerm()!)
        let publishedMessage = String(format: NSLocalizedString("No pages match your search for %@", comment: "The '%@' is a placeholder for the search term."), currentSearchTerm()!)
        
        return noResultsTitles(draftMessage, scheduled: scheduledMessage, trashed: trashedMessage, published: publishedMessage)
    }
    
    private func noResultsTitlesWhenFiltering() -> [PostListStatusFilter:String] {
        
        let draftMessage = NSLocalizedString("You don't have any drafts.", comment: "Displayed when the user views drafts in the pages list and there are no pages")
        let scheduledMessage = NSLocalizedString("You don't have any scheduled pages.", comment: "Displayed when the user views scheduled pages in the pages list and there are no pages")
        let trashedMessage = NSLocalizedString("You don't have any pages in your trash folder.", comment: "Displayed when the user views trashed in the pages list and there are no pages")
        let publishedMessage = NSLocalizedString("You haven't published any pages yet.", comment: "Displayed when the user views published pages in the pages list and there are no pages")
        
        return noResultsTitles(draftMessage, scheduled: scheduledMessage, trashed: trashedMessage, published: publishedMessage)
    }
    
    private func noResultsTitles(draft: String, scheduled: String, trashed: String, published: String) -> [PostListStatusFilter:String] {
        return [.Draft: draft,
                .Scheduled: scheduled,
                .Trashed: trashed,
                .Published: published]
    }
    
    func noResultsMessageText() -> String {
        if syncHelper?.isSyncing == true || isSearching() {
            return ""
        }
        
        let filter = currentPostListFilter()
        
        // currentPostListFilter() may return `nil` at this time (ie: it's been declared as
        // `nullable`).  This will probably change once we can migrate
        // AbstractPostListViewController to Swift, but for the time being we're defining a default
        // filter here.
        //
        // Diego Rey Mendez - 2016/04/18
        //
        let filterType = filter?.filterType ?? .Draft
        var message : String
        
        switch filterType {
        case .Draft:
            message = NSLocalizedString("Would you like to create one?", comment: "Displayed when the user views drafts in the pages list and there are no pages")
        case .Scheduled:
            message = NSLocalizedString("Would you like to schedule a draft to publish?", comment: "Displayed when the user views scheduled pages in the oages list and there are no pages")
        case .Trashed:
            message = NSLocalizedString("Everything you write is solid gold.", comment: "Displayed when the user views trashed pages in the pages list and there are no pages")
        default:
            message = NSLocalizedString("Would you like to publish your first page?", comment: "Displayed when the user views published pages in the pages list and there are no pages")
        }
        
        return message
    }
    
    
    func noResultsButtonText() -> String? {
        if syncHelper?.isSyncing == true || isSearching() {
            return nil
        }
        
        let filter = currentPostListFilter()
        
        // currentPostListFilter() may return `nil` at this time (ie: it's been declared as
        // `nullable`).  This will probably change once we can migrate
        // AbstractPostListViewController to Swift, but for the time being we're defining a default
        // filter here.
        //
        // Diego Rey Mendez - 2016/04/18
        //
        let filterType = filter?.filterType ?? .Draft
        
        switch filterType {
        case .Trashed:
            return ""
        default:
            return NSLocalizedString("Start a Page", comment: "Button title, encourages users to create their first page on their blog.")
        }
    }
    
    func configureAuthorFilter() {
        // Noop
    }
    
    // MARK: - Sync Methods
    
    override internal func postTypeToSync() -> String {
        return PostServiceTypePage
    }
    
    override internal func lastSyncDate() -> NSDate? {
        return blog?.lastPagesSync
    }
    
    // MARK: - TableView Handler Delegate Methods
    
    func entityName() -> String {
        return String(Page.self)
    }
    
    
    func predicateForFetchRequest() -> NSPredicate {
        var predicates = [NSPredicate]()
        
        if let blog = blog {
            let basePredicate = NSPredicate(format: "blog = %@ && original = nil", blog)
            predicates.append(basePredicate)
        }

        let searchText = currentSearchTerm()
        var filterPredicate = currentPostListFilter()?.predicateForFetchRequest
        
        // If we have recently trashed posts, create an OR predicate to find posts matching the filter,
        // or posts that were recently deleted.
        if let recentlyTrashedPostObjectIDs = recentlyTrashedPostObjectIDs
            where searchText?.characters.count == 0 && recentlyTrashedPostObjectIDs.count > 0 {
            
            let trashedPredicate = NSPredicate(format: "SELF IN %@", recentlyTrashedPostObjectIDs)
            
            if let originalFilterPredicate = filterPredicate {
                filterPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [originalFilterPredicate, trashedPredicate])
            } else {
                filterPredicate = trashedPredicate
            }
        }
        
        if let filterPredicate = filterPredicate {
            predicates.append(filterPredicate)
        }
        
        if let searchText = searchText where searchText.characters.count > 0 {
            let searchPredicate = NSPredicate(format: "postTitle CONTAINS[cd] %@", searchText)
            predicates.append(searchPredicate)
        }
        
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return predicate
    }
    
    // MARK: - Table View Handling

    func sectionNameKeyPath() -> String {
        return NSStringFromSelector(#selector(Page.sectionIdentifier))
    }
    
    func tableView(tableView: UITableView, estimatedHeightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return self.dynamicType.pageCellEstimatedRowHeight
    }
    
    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        
        if let page = tableViewHandler?.resultsController.objectAtIndexPath(indexPath) as? Page {
            if cellIdentifierForPage(page) == self.dynamicType.restorePageCellIdentifier {
                return self.dynamicType.pageCellEstimatedRowHeight
            }
            
            let width = CGRectGetWidth(tableView.bounds)
            return self.tableView(tableView, heightForRowAtIndexPath: indexPath, forWidth: width)
        } else {
            return 0
        }
    }
    
    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath, forWidth width: CGFloat) -> CGFloat {
        configureCell(cellForLayout, atIndexPath: indexPath)
        let size = cellForLayout.sizeThatFits(CGSizeMake(width, CGFloat.max))
        let height = ceil(size.height)
        
        return height
    }
    
    func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return self.dynamicType.pageSectionHeaderHeight
    }
    
    func tableView(tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return CGFloat.min
    }
    
    func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView! {
        let sectionInfo = tableViewHandler?.resultsController.sections?[section]
        let nibName = String(PageListSectionHeaderView)
        let headerView = NSBundle.mainBundle().loadNibNamed(nibName, owner: nil, options: nil)[0] as! PageListSectionHeaderView
        
        if let sectionInfo = sectionInfo {
            headerView.setTite(sectionInfo.name)
        }
        
        return headerView
    }
    
    func tableView(tableView: UITableView, viewForFooterInSection section: Int) -> UIView! {
        return UIView(frame: CGRectZero)
    }
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
        
        guard let post = tableViewHandler?.resultsController.objectAtIndexPath(indexPath) as? AbstractPost
            where post.remoteStatus != AbstractPostRemoteStatusPushing && post.status != PostStatusTrash else {
            return
        }
        
        editPage(post)
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let page = tableViewHandler?.resultsController.objectAtIndexPath(indexPath) as! Page
        
        let identifier = cellIdentifierForPage(page)
        let tableViewCell = tableView.dequeueReusableCellWithIdentifier(identifier, forIndexPath: indexPath)
        
        precondition(tableViewCell is PageListCell)
        let cell = tableViewCell as! PageListCell
        
        configureCellAspect(tableViewCell)
        configureCell(cell, atIndexPath: indexPath)
        
        return tableViewCell
    }
    
    private func configureCellAspect(cell: UITableViewCell) {
        cell.accessoryType = .None
        cell.selectionStyle = .None
    }
 
    func configureCell(cell: PageListCell, atIndexPath indexPath: NSIndexPath) {
        cell.delegate = self
        
        guard let page = tableViewHandler?.resultsController.objectAtIndexPath(indexPath) as? Page else {
            preconditionFailure("Object must be a \(String(Page))")
        }
        
        cell.configureCell(page)
    }
    
    private func cellIdentifierForPage(page: Page) -> String {
        var identifier : String
        
        if recentlyTrashedPostObjectIDs?.containsObject(page.objectID) == true && currentPostListFilter()?.filterType != .Trashed {
            identifier = self.dynamicType.restorePageCellIdentifier
        } else {
            identifier = self.dynamicType.pageCellIdentifier
        }
        
        return identifier
    }
    
    // MARK: - Post Actions
    
    func createPost() {
        let navController : UINavigationController
        
        if EditPageViewController.isNewEditorEnabled() {
            let postViewController = EditPageViewController(draftForBlog: blog)
            
            navController = UINavigationController(rootViewController: postViewController)
            navController.restorationIdentifier = WPEditorNavigationRestorationID
            navController.restorationClass = EditPageViewController.self
        } else {
            let editPostViewController = WPLegacyEditPageViewController(draftForLastUsedBlog: ())
            
            navController = UINavigationController(rootViewController: editPostViewController)
            navController.restorationIdentifier = WPLegacyEditorNavigationRestorationID
            navController.restorationClass = WPLegacyEditPageViewController.self
        }
        
        navController.modalPresentationStyle = .FullScreen
        
        presentViewController(navController, animated: true, completion: nil)
        
        WPAppAnalytics.track(.EditorCreatedPost, withProperties: ["tap_source": "posts_view"], withBlog: blog)
    }
    
    private func editPage(apost: AbstractPost) {
        WPAnalytics.track(.PostListEditAction, withProperties: propertiesForAnalytics())
        
        if EditPageViewController.isNewEditorEnabled() {
            let pageViewController = EditPageViewController(post: apost, mode: kWPPostViewControllerModePreview)
            
            navigationController?.pushViewController(pageViewController, animated: true)
        } else {
            // In legacy mode, view means edit
            let editPageViewController = WPLegacyEditPageViewController(post: apost)
            let navController = UINavigationController(rootViewController: editPageViewController)
            
            navController.modalPresentationStyle = .FullScreen
            navController.restorationIdentifier = WPLegacyEditorNavigationRestorationID
            navController.restorationClass = WPLegacyEditPageViewController.self
            
            presentViewController(navController, animated: true, completion: nil)
        }
    }
    
    private func draftPage(apost: AbstractPost) {
        WPAnalytics.track(.PostListDraftAction, withProperties: propertiesForAnalytics())
        
        let previousStatus = apost.status
        apost.status = PostStatusDraft
        
        let contextManager = ContextManager.sharedInstance()
        let postService = PostService(managedObjectContext: contextManager.mainContext)
        
        postService.uploadPost(apost, success: nil) { [weak self] (error) in
            apost.status = previousStatus
            
            if let strongSelf = self {
                contextManager.saveContext(strongSelf.managedObjectContext())
            }
            
            WPError.showXMLRPCErrorAlert(error)
        }
    }
    
    func promptThatPostRestoredToFilter(filter: PostListFilter) {
        var message = NSLocalizedString("Page Restored to Drafts", comment: "Prompts the user that a restored page was moved to the drafts list.")
        
        switch filter.filterType {
        case .Published:
            message = NSLocalizedString("Page Restored to Published", comment: "Prompts the user that a restored page was moved to the published list.")
        break
        case .Scheduled:
            message = NSLocalizedString("Page Restored to Scheduled", comment: "Prompts the user that a restored page was moved to the scheduled list.")
            break
        default:
            break
        }
        
        let alertCancel = NSLocalizedString("OK", comment: "Title of an OK button. Pressing the button acknowledges and dismisses a prompt.")
        
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .Alert)
        alertController.addCancelActionWithTitle(alertCancel, handler: nil)
        alertController.presentFromRootViewController()
    }
    
    // MARK: - Filter Related
    
    func keyForCurrentListStatusFilter() -> String {
        return self.dynamicType.currentPageListStatusFilterKey
    }
    
    // MARK: - Cell Delegate Methods
    
    func cell(cell: UITableViewCell!, receivedMenuActionFromButton button: UIButton, forProvider contentProvider: WPPostContentViewProvider!) {
        let page = contentProvider as! Page
        let objectID = page.objectID
        
        let viewButtonTitle = NSLocalizedString("View", comment: "Label for a button that opens the page when tapped.")
        let draftButtonTitle = NSLocalizedString("Move to Draft", comment: "Label for a button that moves a page to the draft folder")
        let publishButtonTitle = NSLocalizedString("Publish Immediately", comment: "Label for a button that moves a page to the published folder, publishing with the current date/time.")
        let trashButtonTitle = NSLocalizedString("Move to Trash", comment: "Label for a button that moves a page to the trash folder")
        let cancelButtonTitle = NSLocalizedString("Cancel", comment: "Label for a cancel button")
        let deleteButtonTitle = NSLocalizedString("Delete Permanently", comment: "Label for a button permanently deletes a page.")
        
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .ActionSheet)
        alertController.addCancelActionWithTitle(cancelButtonTitle, handler: nil)
        
        if let filter = currentPostListFilter()?.filterType {
            if filter == .Trashed {
                alertController.addActionWithTitle(publishButtonTitle, style: .Default, handler: { [weak self] (action) in
                    guard let strongSelf = self,
                        let page = strongSelf.pageForObjectID(objectID) else {
                        return
                    }
                    
                    strongSelf.publishPost(page)
                })
                
                alertController.addActionWithTitle(draftButtonTitle, style: .Default, handler: { [weak self] (action) in
                    guard let strongSelf = self,
                        let page = strongSelf.pageForObjectID(objectID) else {
                            return
                    }
                    
                    strongSelf.draftPage(page)
                })
                
                alertController.addActionWithTitle(deleteButtonTitle, style: .Default, handler: { [weak self] (action) in
                    guard let strongSelf = self,
                        let page = strongSelf.pageForObjectID(objectID) else {
                            return
                    }
                    
                    strongSelf.deletePost(page)
                })
            } else if filter == .Published {
                alertController.addActionWithTitle(viewButtonTitle, style: .Default, handler: { [weak self] (action) in
                    guard let strongSelf = self,
                        let page = strongSelf.pageForObjectID(objectID) else {
                            return
                    }
                    
                    strongSelf.viewPost(page)
                })
                
                alertController.addActionWithTitle(draftButtonTitle, style: .Default, handler: { [weak self] (action) in
                    guard let strongSelf = self,
                        let page = strongSelf.pageForObjectID(objectID) else {
                            return
                    }
                    
                    strongSelf.draftPage(page)
                })
                
                alertController.addActionWithTitle(trashButtonTitle, style: .Default, handler: { [weak self] (action) in
                    guard let strongSelf = self,
                        let page = strongSelf.pageForObjectID(objectID) else {
                            return
                    }
                    
                    strongSelf.deletePost(page)
                })
            } else {
                alertController.addActionWithTitle(viewButtonTitle, style: .Default, handler: { [weak self] (action) in
                    guard let strongSelf = self,
                        let page = strongSelf.pageForObjectID(objectID) else {
                            return
                    }

                    strongSelf.viewPost(page)
                })
                
                alertController.addActionWithTitle(publishButtonTitle, style: .Default, handler: { [weak self] (action) in
                    guard let strongSelf = self,
                        let page = strongSelf.pageForObjectID(objectID) else {
                            return
                    }
                    
                    strongSelf.publishPost(page)
                })
                
                alertController.addActionWithTitle(trashButtonTitle, style: .Default, handler: { [weak self] (action) in
                    guard let strongSelf = self,
                        let page = strongSelf.pageForObjectID(objectID) else {
                            return
                    }
                    
                    strongSelf.deletePost(page)
                })
            }
        }
        
        WPAnalytics.track(.PostListOpenedCellMenu, withProperties: propertiesForAnalytics())
        
        if !UIDevice.isPad() {
            presentViewController(alertController, animated: true, completion: nil)
            return
        }
        
        alertController.modalPresentationStyle = .Popover
        presentViewController(alertController, animated: true, completion: nil)
        
        if let presentationController = alertController.popoverPresentationController {
            presentationController.permittedArrowDirections = .Any
            presentationController.sourceView = button
            presentationController.sourceRect = button.bounds
        }
    }

    func pageForObjectID(objectID: NSManagedObjectID) -> Page? {
        
        var pageManagedOjbect : NSManagedObject
        
        do {
            pageManagedOjbect = try managedObjectContext().existingObjectWithID(objectID)
            
        } catch let error as NSError {
            DDLogSwift.logError("\(NSStringFromClass(self.dynamicType)), \(#function), \(error)")
            return nil
        } catch _ {
            DDLogSwift.logError("\(NSStringFromClass(self.dynamicType)), \(#function), Could not find Page with ID \(objectID)")
            return nil
        }
        
        let page = pageManagedOjbect as? Page
        return page
    }
    
    func cell(cell: UITableViewCell!, receivedRestoreActionForProvider contentProvider: WPPostContentViewProvider!) {
        if let apost = contentProvider as? AbstractPost {
            restorePost(apost)
        }
    }
}
