import UIKit
import WordPressComAnalytics
import WordPressShared

/// Provides a form and functionality for signing a user in to WordPress.com
///
@objc class SigninWPComViewController : NUXAbstractViewController, SigninWPComSyncHandler, SigninKeyboardResponder
{

    @IBOutlet weak var usernameField: WPWalkthroughTextField!
    @IBOutlet weak var passwordField: WPWalkthroughTextField!
    @IBOutlet weak var submitButton: NUXSubmitButton!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet var bottomContentConstraint: NSLayoutConstraint!
    @IBOutlet var verticalCenterConstraint: NSLayoutConstraint!
    var onePasswordButton: UIButton!

    var immediateSignin = false;

    lazy var loginFacade: LoginFacade = {
        let facade = LoginFacade()
        facade.delegate = self
        return facade
    }()


    /// A convenience method for obtaining an instance of the controller from a storyboard.
    ///
    /// - Parameters:
    ///     - loginFields: A LoginFields instance containing any prefilled credentials.
    ///     - immediateSignin: Whether the controller should attempt to signin immediately.
    ///
    class func controller(loginFields: LoginFields, immediateSignin: Bool = false) -> SigninWPComViewController {
        let storyboard = UIStoryboard(name: "Signin", bundle: NSBundle.mainBundle())
        let controller = storyboard.instantiateViewControllerWithIdentifier("SigninWPComViewController") as! SigninWPComViewController
        controller.loginFields = loginFields
        controller.immediateSignin = immediateSignin
        return controller
    }


    // MARK: - Lifecycle Methods


    override func viewDidLoad() {
        super.viewDidLoad()

        setupOnePasswordButtonIfNeeded()
        configureStatusLabel("")
    }


    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        // Update special case login fields.
        loginFields.userIsDotCom = true

        configureTextFields()
        configureSubmitButton(false)
        configureViewForEditingIfNeeded()
    }


    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        registerForKeyboardEvents(#selector(SigninEmailViewController.handleKeyboardWillShow(_:)),
                                  keyboardWillHideAction: #selector(SigninEmailViewController.handleKeyboardWillHide(_:)))

        if immediateSignin {
            validateForm()
            immediateSignin = false
        }
    }


    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        unregisterForKeyboardEvents()
    }


    // MARK: Setup and Configuration


    /// Sets up a 1Password button if 1Password is available.
    ///
    func setupOnePasswordButtonIfNeeded() {
        WPStyleGuide.configureOnePasswordButtonForTextfield(usernameField,
                                                            target: self,
                                                            selector: #selector(SigninWPComViewController.handleOnePasswordButtonTapped(_:)))
    }


    /// Configures the content of the text fields based on what is saved in `loginFields`.
    ///
    func configureTextFields() {
        usernameField.text = loginFields.username
        passwordField.text = loginFields.password
    }


    /// Displays the specified text in the status label. 
    /// 
    /// - Parameters:
    ///     - message: The text to display in the label.
    ///
    func configureStatusLabel(message: String) {
        statusLabel.text = message
    }


    /// Configures the appearance and state of the submit button.
    ///
    func configureSubmitButton(animating: Bool) {
        submitButton.showActivityIndicator(animating)

        submitButton.enabled = (
            !animating &&
                !loginFields.username.isEmpty &&
                !loginFields.password.isEmpty
        )
    }


    /// Configure the view's loading state.
    ///
    /// - Parameters:
    ///     - loading: True if the form should be configured to a "loading" state.
    ///
    func configureViewLoading(loading: Bool) {
        usernameField.enabled = !loading
        passwordField.enabled = !loading
        
        configureSubmitButton(loading)
    }


    /// Configure the view for an editing state. Should only be called from viewWillAppear
    /// as this method skips animating any change in height.
    ///
    func configureViewForEditingIfNeeded() {
        // Check the helper to determine whether an editiing state should be assumed.
        // Check the helper to determine whether an editiing state should be assumed.
        adjustViewForKeyboard(SigninEditingState.signinEditingStateActive)
        if SigninEditingState.signinEditingStateActive {
            passwordField.becomeFirstResponder()
        }
    }


    // MARK: - Instance Methods


    /// Validates what is entered in the various form fields and, if valid,
    /// proceeds with the submit action.
    ///
    func validateForm() {
        view.endEditing(true)

        // Is everything filled out?
        if !SigninHelpers.validateFieldsPopulatedForSignin(loginFields) {
            WPError.showAlertWithTitle(NSLocalizedString("Error", comment: "Title of an error message"),
                                       message: NSLocalizedString("Please fill out all the fields", comment: "A short prompt asking the user to properly fill out all login fields."),
                                       withSupportButton: false)

            return
        }

        // If the username is reservied the user might be trying to sign in to a self-hosted site.
        if SigninHelpers.isUsernameReserved(loginFields.username) {
            let alert = UIAlertController(title: NSLocalizedString("Self-hosted Site?", comment: "Title of a notice to the user."),
                                          message: NSLocalizedString("It looks like you're signing in to a self-hosted site.  Enter your site's URL on the next screen.", comment: "A brief notice to the user. Explaining the next step when signing in."),
                                          preferredStyle: .Alert)
            alert.addDefaultActionWithTitle(NSLocalizedString("OK", comment: "A button label. Tapping dismisses a prompt."), handler: { (action: UIAlertAction) in
                self.signinToSelfHostedSite()
            })
            presentViewController(alert, animated: true, completion: nil)
            return
        }

        configureViewLoading(true)

        loginFacade.signInWithLoginFields(loginFields)
    }


    /// Update safari stored credentials. Call after a successful sign in.
    ///
    func updateSafariCredentialsIfNeeded() {
        SigninHelpers.updateSafariCredentialsIfNeeded(loginFields)
    }


    func signinToSelfHostedSite() {
        let controller = SigninSelfHostedViewController.controller(loginFields);
        navigationController?.pushViewController(controller, animated: true)
    }


    // MARK: - Actions


    @IBAction func handleTextFieldDidChange(sender: UITextField) {
        loginFields.username = usernameField.nonNilTrimmedText()
        loginFields.password = passwordField.nonNilTrimmedText()

        configureSubmitButton(false)
    }


    @IBAction func handleSubmitButtonTapped(sender: UIButton) {
        validateForm()
    }


    @IBAction func handleForgotPasswordButtonTapped(sender: UIButton) {
        SigninHelpers.openForgotPasswordURL(loginFields)
    }


    func handleOnePasswordButtonTapped(sender: UIButton) {
        view.endEditing(true)

        SigninHelpers.fetchOnePasswordCredentials(self, sourceView: sender, loginFields: loginFields) { [unowned self] (loginFields) in
            self.validateForm()
        }
    }


    @IBAction func handleSelfHostedButtonTapped(sender: UIButton) {
        signinToSelfHostedSite()
    }


    // MARK: - Keyboard Notifications


    func handleKeyboardWillShow(notification: NSNotification) {
        keyboardWillShow(notification)
    }


    func handleKeyboardWillHide(notification: NSNotification) {
        keyboardWillHide(notification)
    }
}


extension SigninWPComViewController: LoginFacadeDelegate {

    func finishedLoginWithUsername(username: String!, authToken: String!, requiredMultifactorCode: Bool) {
        syncWPCom(username, authToken: authToken, requiredMultifactor: requiredMultifactorCode)
    }


    func displayLoginMessage(message: String!) {
        configureStatusLabel(message)
    }


    func displayRemoteError(error: NSError!) {
        configureStatusLabel("")
        configureViewLoading(false)
        displayError(error)
    }


    func needsMultifactorCode() {
        configureStatusLabel("")
        configureViewLoading(false)

        WPAppAnalytics.track(.TwoFactorCodeRequested)
        // Credentials were good but a 2fa code is needed.
        loginFields.shouldDisplayMultifactor = true // technically not needed
        let controller = Signin2FAViewController.controller(loginFields)
        navigationController?.pushViewController(controller, animated: true)
    }
}


extension SigninWPComViewController: UITextFieldDelegate {
    func textFieldShouldReturn(textField: UITextField) -> Bool {
        if textField == usernameField {
            passwordField.becomeFirstResponder()
        } else if submitButton.enabled {
            validateForm()
        }
        return true
    }
}
