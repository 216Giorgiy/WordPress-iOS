import UIKit
import NSURL_IDN
import WordPressComAnalytics

/// A collection of helper methods for NUX.
///
@objc class SigninHelpers: NSObject
{
    private static let AuthenticationEmailKey = "AuthenticationEmailKey"

    // Stubbed method for implementing A/B testing between the old and new signin flows.
    class func useNewSigninFlow() -> Bool {
        return true
    }


    // Helper used by app delegate
    class func showSigninFromPresenter(presenter: UIViewController, animated: Bool, thenEditor: Bool) {
        if useNewSigninFlow() {
            let controller = SigninEmailViewController.controller();
            controller.dismissBlock = {(cancelled) in
                // Show the editor if requested, and we weren't cancelled.
                if !cancelled && thenEditor {
                    WPTabBarController.sharedInstance().showPostTab()
                    return
                }
            }

            let navController = NUXNavigationController(rootViewController: controller)
            presenter.presentViewController(navController, animated: animated, completion: nil)

        } else {
            let context = ContextManager.sharedInstance().mainContext
            let accountService = AccountService(managedObjectContext: context)
            let blogService = BlogService(managedObjectContext: context)

            let hasWPcomAcctButNoSelfHostedBLogs = (accountService.defaultWordPressComAccount() != nil) && blogService.blogCountSelfHosted() == 0

            let controller = LoginViewController()
            controller.showEditorAfterAddingSites = thenEditor
            controller.cancellable = hasWPcomAcctButNoSelfHostedBLogs
            controller.dismissBlock = { (cancelled) in
                presenter.dismissViewControllerAnimated(true, completion: nil)
            }

            let navController = RotationAwareNavigationViewController(rootViewController: controller)
            navController.navigationBar.translucent = false
            presenter.presentViewController(navController, animated: animated, completion: nil)
        }
    }


    // Helper used by the BlogListViewController
    class func showSigninForSelfHostedSite(presentingController: UIViewController) {
        if useNewSigninFlow() {
            let controller = SigninSelfHostedViewController.controller(LoginFields())
            let navController = NUXNavigationController(rootViewController: controller)
            presentingController.presentViewController(navController, animated: true, completion: nil)

        } else {
            let controller = LoginViewController()
            controller.cancellable = true
            controller.prefersSelfHosted = true
            controller.dismissBlock = {(canceled) in
                presentingController.dismissViewControllerAnimated(true, completion: nil)
            }

            let navController = UINavigationController(rootViewController: controller)
            presentingController.presentViewController(navController, animated: true, completion: nil)
        }
    }


    // Helper used by WPAuthTokenIssueSolver
    class func signinForWPComFixingAuthToken(onDismissed: ((cancelled: Bool) -> Void)?) -> UIViewController {
        let context = ContextManager.sharedInstance().mainContext
        if useNewSigninFlow() {
            let loginFields = LoginFields()
            if let account = AccountService(managedObjectContext: context).defaultWordPressComAccount() {
                loginFields.username = account.username
            }

            let controller = SigninWPComViewController.controller(loginFields)
            controller.dismissBlock = onDismissed

            let navController = NUXNavigationController(rootViewController: controller)
            return navController

        } else {
            let blogService = BlogService(managedObjectContext: context)
            let cancellable = blogService.blogCountSelfHosted() > 0

            let controller = LoginViewController()
            controller.onlyDotComAllowed = true
            controller.shouldReauthenticateDefaultAccount = true
            controller.cancellable = cancellable
            controller.dismissBlock = {(cancelled) in
                onDismissed?(cancelled: cancelled)
            }

            return controller
        }
    }


    // Helper used by WPError
    class func showSigninForWPComFixingAuthToken() {
        let controller = signinForWPComFixingAuthToken(nil)
        if useNewSigninFlow() {
            let navController = NUXNavigationController(rootViewController: controller)
            UIApplication.sharedApplication().keyWindow?.rootViewController?.presentViewController(navController, animated: true, completion: nil)
        } else {
            LoginViewController.presentModalReauthScreen()
        }
    }


    /// Present a signin view controller to handle an authentication link.
    ///
    /// - Parameters:
    ///     - url: The authentication URL
    ///     - rootViewController: The view controller to act as the presenter for
    ///     the signin view controller. By convention this is the app's root vc.
    ///
    class func openAuthenticationURL(url: NSURL, fromRootViewController rootViewController: UIViewController) -> Bool {
        guard let token = url.query?.dictionaryFromQueryString().stringForKey("token") else {
            DDLogSwift.logError("Signin Error: The authentication URL did not have the expected path.")
            return false
        }

        let accountService = AccountService(managedObjectContext: ContextManager.sharedInstance().mainContext)
        if let account = accountService.defaultWordPressComAccount() {
            DDLogSwift.logInfo("App opened with authentication link but there is already an existing wpcom account. \(account)")
            return false
        }

        var controller: UIViewController
        if let email = getEmailAddressForTokenAuth() {
            controller = SigninLinkAuthViewController.controller(email, token: token)
            WPAppAnalytics.track(.LoginMagicLinkOpened)
        } else {
            controller = SigninEmailViewController.controller()
        }
        let navController = UINavigationController(rootViewController: controller)

        // The way the magic link flow works the `SigninLinkMailViewController`,
        // or some other view controller, might still be presented when the app
        // is resumed by tapping on the auth link.
        // We need to do a little work to present the SigninLinkAuth controller 
        // from the right place.
        // - If the rootViewController is not presenting another vc then just
        // present the auth controller.
        // - If the rootViewController is presenting another NUX vc, dismiss the 
        // NUX vc then present the auth controller.
        // - If the rootViewController is presenting *any* other vc, present the
        // auth controller from the presented vc.
        if let presenter = rootViewController.presentedViewController where presenter.isKindOfClass(NUXNavigationController.self) {
            rootViewController.dismissViewControllerAnimated(false, completion: {
                rootViewController.presentViewController(navController, animated: false, completion: nil)
            })
        } else {
            let presenter = controllerForAuthControllerPresenter(rootViewController)
            presenter.presentViewController(navController, animated: false, completion: nil)
        }

        deleteEmailAddressForTokenAuth()
        return true
    }


    /// Determine the proper UIViewController to use as a presenter for the auth controller.
    ///
    /// - Parameters: 
    ///     - controller: A UIViewController. By convention this should be the app's rootViewController
    ///
    /// - Return: The view controller to use as the presenter.
    ///
    class func controllerForAuthControllerPresenter(controller: UIViewController) -> UIViewController {
        var presenter = controller
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        return presenter
    }


    /// Check if the specified controller was presented from the application's root vc.
    ///
    /// - Parameters:
    ///     - controller: A UIViewController
    ///
    /// - Return: True if presented from the root vc.
    ///
    class func controllerWasPresentedFromRootViewController(controller: UIViewController) -> Bool {
        guard let presentingViewController = controller.presentingViewController else {
            return false
        }
        return presentingViewController == UIApplication.sharedApplication().keyWindow?.rootViewController
    }


    /// The base site URL path derived from `loginFields.siteUrl`
    ///
    /// - Parameters:
    ///     - string: The source URL as a string.
    ///
    /// - Returns: The base URL or an empty string.
    ///
    class func baseSiteURL(string: String) -> String {
        guard let siteURL = NSURL(string: NSURL.IDNDecodedURL(string)) else {
            return ""
        }

        var path = siteURL.absoluteString.lowercaseString

        if path.isWordPressComPath() {
            if siteURL.scheme.characters.count == 0 {
                path = "https://\(path)"
            } else if path.rangeOfString("http://") != nil {
                path = path.stringByReplacingOccurrencesOfString("http://", withString: "https://")
            }
        } else if siteURL.scheme.characters.count == 0 {
            path = "http://\(path)"
        }

        path = path
            .trimSuffix(regexp: "/wp-login.php")
            .trimSuffix(regexp: "/wp-admin/?")
            .trimSuffix(regexp: "/?")

        return path
    }


    // MARK: - Validation Helpers


    /// Checks if the passed string matches a reserved username.
    /// 
    /// - Parameters:
    ///     - username: The username to test.
    ///
    class func isUsernameReserved(username: String) -> Bool {
        let name = username.lowercaseString.trim()
        return ["admin", "administrator", "root"].contains(name)
    }


    /// Checks whether credentials have been populated.
    ///
    /// - Parameters:
    ///     - loginFields: An instance of LoginFields to check
    ///
    /// - Returns: True if credentails have been provided. False otherwise.
    ///
    class func validateFieldsPopulatedForSignin(loginFields: LoginFields) -> Bool {
        return !loginFields.username.isEmpty &&
            !loginFields.password.isEmpty &&
            ( loginFields.userIsDotCom || !loginFields.siteUrl.isEmpty )
    }


    /// Simple validation check to confirm LoginFields has a valid site URL.
    ///
    /// - Parameters:
    ///     - loginFields: An instance of LoginFields to check
    ///
    /// - Returns: True if the siteUrl contains a valid URL. False otherwise.
    ///
    class func validateSiteForSignin(loginFields: LoginFields) -> Bool {
        guard let url = NSURL(string: NSURL.IDNEncodedURL(loginFields.siteUrl)) else {
            return false
        }

        if url.absoluteString.isEmpty {
            return false
        }

        return true
    }


    // MARK: - Helpers for Saved Magic Link Email


    /// Saves the specified email address in NSUserDefaults
    ///
    /// - Parameters:
    ///     - email: The email address to save.
    ///
    class func saveEmailAddressForTokenAuth(email: String) {
        NSUserDefaults.standardUserDefaults().setObject(email, forKey: AuthenticationEmailKey)
    }


    /// Removes the saved email address from NSUserDefaults
    ///
    class func deleteEmailAddressForTokenAuth() {
        NSUserDefaults.standardUserDefaults().removeObjectForKey(AuthenticationEmailKey)
    }


    /// Fetches a saved email address if one exists.
    ///
    /// - Returns: The email address as a string or nil.
    ///
    class func getEmailAddressForTokenAuth() -> String? {
        return NSUserDefaults.standardUserDefaults().stringForKey(AuthenticationEmailKey)
    }


    // MARK: - Other Helpers


    /// Opens Safari to display the forgot password page for a wpcom or self-hosted 
    /// based on the passed LoginFields instance.
    ///
    /// - Parameters:
    ///     - loginFields: A LoginFields instance.
    ///
    class func openForgotPasswordURL(loginFields: LoginFields) {
        let baseURL = loginFields.userIsDotCom ? "https://wordpress.com" : SigninHelpers.baseSiteURL(loginFields.siteUrl)
        let forgotPasswordURL = NSURL(string: baseURL + "/wp-login.php?action=lostpassword&redirect_to=wordpress%3A%2F%2F")!
        UIApplication.sharedApplication().openURL(forgotPasswordURL)
    }



    // MARK: - 1Password Helper


    /// Request credentails from 1Password (if supported)
    ///
    /// - Parameters:
    ///     - sender: A UIView. Typically the button the user tapped on.
    ///
    class func fetchOnePasswordCredentials(controller: UIViewController, sourceView: UIView, loginFields: LoginFields, success: ((loginFields: LoginFields) -> Void)) {

        let loginURL = loginFields.userIsDotCom ? "wordpress.com" : loginFields.siteUrl

        let onePasswordFacade = OnePasswordFacade()
        onePasswordFacade.findLoginForURLString(loginURL, viewController: controller, sender: sourceView, completion: { (username: String!, password: String!, oneTimePassword: String!, error: NSError!) in
            guard error == nil else {
                DDLogSwift.logError("OnePassword Error: \(error.localizedDescription)")
                WPAppAnalytics.track(.OnePasswordFailed)
                return
            }

            guard let username = username, password = password else {
                return
            }

            if username.isEmpty || password.isEmpty {
                return
            }

            loginFields.username = username
            loginFields.password = password

            if oneTimePassword != nil {
                loginFields.multifactorCode = oneTimePassword
            }

            WPAppAnalytics.track(.OnePasswordLogin)

            success(loginFields: loginFields)
        })
        
    }


    // MARK: - Safari Stored Credentials Helpers


    static let LoginSharedWebCredentialFQDN: CFString = "wordpress.com"
    typealias SharedWebCredentialsCallback = ((credentialsFound: Bool, username: String?, password: String?) -> Void)


    /// Update safari stored credentials.
    ///
    /// - Parameters:
    ///     - loginFields: An instance of LoginFields
    ///
    class func updateSafariCredentialsIfNeeded(loginFields: LoginFields) {
        // Paranioa. Don't try and update credentials for self-hosted.
        if !loginFields.userIsDotCom {
            return;
        }

        // If the user changed screen names, don't try and update/create a new shared web credential.
        // We'll let Safari handle creating newly saved usernames/passwords.
        if loginFields.safariStoredUsernameHash != loginFields.username.hash {
            return
        }

        // If the user didn't change the password from previousl filled password no update is needed.
        if loginFields.safariStoredPasswordHash == loginFields.password.hash {
            return
        }

        // Update the shared credential
        let username: CFString = loginFields.username
        let password: CFString = loginFields.password

        SecAddSharedWebCredential(LoginSharedWebCredentialFQDN, username, password, { (error: CFError?) in
            guard error == nil else {
                let err = error! as NSError
                DDLogSwift.logError("Error occurred updating shared web credential: \(err.localizedDescription)");
                return
            }
            dispatch_async(dispatch_get_main_queue(), {
                WPAppAnalytics.track(.LoginAutoFillCredentialsUpdated)
            })
        })
    }


    /// Request shared safari credentials if they exist.
    ///
    /// - Parameters:
    ///     - completion: A completion block.
    ///
    class func requestSharedWebCredentials(completion: SharedWebCredentialsCallback) {
        SecRequestSharedWebCredential(LoginSharedWebCredentialFQDN, nil, { (credentials: CFArray?, error: CFError?) in
            DDLogSwift.logInfo("Completed requesting shared web credentials")
            guard error == nil else {
                let err = error! as NSError
                if err.code == -25300 {
                    // An OSStatus of -25300 is expected when no saved credentails are found.
                    DDLogSwift.logInfo("No shared web credenitals found.")
                } else {
                    DDLogSwift.logError("Error requesting shared web credentials: \(err.localizedDescription)")
                }
                dispatch_async(dispatch_get_main_queue(), {
                    completion(credentialsFound: false, username: nil, password: nil)
                })
                return
            }

            guard let credentials = credentials where CFArrayGetCount(credentials) > 0 else {
                // Saved credentials exist but were not selected.
                dispatch_async(dispatch_get_main_queue(), {
                    completion(credentialsFound: true, username: nil, password: nil)
                })
                return
            }

            // What a chore!
            let unsafeCredentials = CFArrayGetValueAtIndex(credentials, 0)
            let credentialsDict = unsafeBitCast(unsafeCredentials, CFDictionaryRef.self)

            let unsafeUsername = CFDictionaryGetValue(credentialsDict, unsafeAddressOf(kSecAttrAccount))
            let usernameStr = unsafeBitCast(unsafeUsername, CFString.self) as String

            let unsafePassword = CFDictionaryGetValue(credentialsDict, unsafeAddressOf(kSecSharedPassword))
            let passwordStr = unsafeBitCast(unsafePassword, CFString.self) as String

            dispatch_async(dispatch_get_main_queue(), {
                completion(credentialsFound: true, username: usernameStr, password: passwordStr)
            })
        })
    }
}
