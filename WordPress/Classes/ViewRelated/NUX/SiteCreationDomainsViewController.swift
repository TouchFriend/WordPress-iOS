import UIKit
import SVProgressHUD

class SiteCreationDomainsViewController: UITableViewController {
    var helpBadge: WPNUXHelpBadgeLabel!
    var helpButton: UIButton!

    open var siteName: String?

    var service: DomainsService?
    private var siteTitleSuggestions: [String] = []
    private var searchSuggestions: [String] = []
    private var isSearching: Bool = false

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        tableView.register(UINib(nibName: "SiteCreationDomainSearchTableViewCell", bundle: nil), forCellReuseIdentifier: SiteCreationDomainSearchTableViewCell.cellIdentifier)
        setupBackgroundTapGestureRecognizer()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        WPStyleGuide.configureColors(for: view, andTableView: tableView)
        tableView.layoutMargins = WPStyleGuide.edgeInsetForLoginTextFields()

        let (helpButtonResult, helpBadgeResult) = addHelpButtonToNavController()
        helpButton = helpButtonResult
        helpBadge = helpBadgeResult

        navigationItem.title = NSLocalizedString("Create New Site", comment: "Title for the site creation flow.")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // only procede with initial search if we don't have site title suggestions yet (hopefully only the first time)
        guard siteTitleSuggestions.count < 1,
            let nameToSearch = siteName else {
            return
        }

        suggestDomains(for: nameToSearch) { [weak self] (suggestions) in
            self?.siteTitleSuggestions = suggestions
            self?.tableView.reloadSections(IndexSet(integersIn: Sections.searchField.rawValue...Sections.suggestions.rawValue), with: .automatic)
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.isPad() ? .all : .portrait
    }

    /// Fetches new domain suggestions based on the provided string
    ///
    /// - Parameters:
    ///   - searchTerm: string to base suggestions on
    ///   - addSuggestions: function to call when results arrive
    private func suggestDomains(for searchTerm: String, addSuggestions: @escaping (_: [String]) ->()) {
        guard !isSearching else {
            return
        }

        isSearching = true

        let api = WordPressComRestApi(oAuthToken: "")
        let service = DomainsService(managedObjectContext: ContextManager.sharedInstance().mainContext, remote: DomainsServiceRemote(wordPressComRestApi: api))
        SVProgressHUD.show(withStatus: NSLocalizedString("Loading domains", comment: "Shown while the app waits for the domain suggestions web service to return during the site creation process."))
        service.getDomainSuggestions(base: searchTerm, success: { [weak self] (suggestions) in
            self?.isSearching = false
            SVProgressHUD.dismiss()
            addSuggestions(suggestions)
        }) { [weak self] (error) in
            self?.isSearching = false
        }
    }

    // MARK: background gesture recognizer

    /// Sets up a gesture recognizer to detect taps on the view, but not its content.
    ///
    @objc func setupBackgroundTapGestureRecognizer() {
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(SiteCreationDomainsViewController.handleBackgroundTapGesture(_:)))
        gestureRecognizer.cancelsTouchesInView = false
        view.addGestureRecognizer(gestureRecognizer)
    }

    @objc func handleBackgroundTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
        view.endEditing(true)
    }
}

// MARK: - LoginWithLogoAndHelpViewController methods

extension SiteCreationDomainsViewController: LoginWithLogoAndHelpViewController {
    func handleHelpButtonTapped(_ sender: AnyObject) {
        displaySupportViewController(sourceTag: .wpComCreateSiteDomain)
    }

    func handleHelpshiftUnreadCountUpdated(_ notification: Foundation.Notification) {
        let count = HelpshiftUtils.unreadNotificationCount()
        helpBadge.text = "\(count)"
        helpBadge.isHidden = (count == 0)
    }
}

// MARK: UITableViewDataSource

extension SiteCreationDomainsViewController {
    fileprivate enum Sections: Int {
        case titleAndDescription = 0
        case searchField = 1
        case suggestions = 2

        static var count: Int {
            return suggestions.rawValue + 1
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case Sections.titleAndDescription.rawValue:
            return 1
        case Sections.searchField.rawValue:
            if siteTitleSuggestions.count == 0 {
                return 0
            } else {
                return 1
            }
        case Sections.suggestions.rawValue:
            return searchSuggestions.count > 0 ? searchSuggestions.count : siteTitleSuggestions.count
        default:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        switch indexPath.section {
        case Sections.titleAndDescription.rawValue:
            cell = titleAndDescriptionCell()
        case Sections.searchField.rawValue:
            cell = searchFieldCell()
        case Sections.suggestions.rawValue:
            fallthrough
        default:
            let suggestion: String
            if searchSuggestions.count > 0 {
                suggestion = searchSuggestions[indexPath.row]
            } else {
                suggestion = siteTitleSuggestions[indexPath.row]
            }
            cell = suggestionCell(domain: suggestion)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        if section == Sections.suggestions.rawValue {
            let footer = UIView()
            footer.backgroundColor = WPStyleGuide.greyLighten20()
            return footer
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if section == Sections.suggestions.rawValue {
            return 0.5
        }
        return 0
    }

    // MARK: table view cells

    private func titleAndDescriptionCell() -> UITableViewCell {
        let title = NSLocalizedString("Step 4 of 4", comment: "Title for last step in the site creation process.").localizedUppercase
        let description = NSLocalizedString("Pick an available \"yourname.wordpress.com\" address to let people find you on the web.", comment: "Description of how to pick a domain name during the site creation process")
        let cell = LoginSocialErrorCell(title: title, description: description)
        cell.selectionStyle = .none
        return cell
    }

    private func searchFieldCell() -> SiteCreationDomainSearchTableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: SiteCreationDomainSearchTableViewCell.cellIdentifier) as? SiteCreationDomainSearchTableViewCell else {
            return SiteCreationDomainSearchTableViewCell(placeholder: "")
        }
        cell.delegate = self
        cell.selectionStyle = .none
        return cell
    }

    private func suggestionCell(domain: String) -> UITableViewCell {
        let cell = UITableViewCell()

        cell.accessoryType = .disclosureIndicator
        cell.textLabel?.attributedText = styleDomain(domain)
        cell.textLabel?.textColor = WPStyleGuide.grey()
        cell.indentationWidth = 20.0
        cell.indentationLevel = 1
        return cell
    }

    private func styleDomain(_ domain: String) -> NSAttributedString {
        let styledDomain: NSMutableAttributedString = NSMutableAttributedString(string: domain)
        guard let dotPosition = domain.index(of: ".") else {
            return styledDomain
        }
        styledDomain.addAttribute(.foregroundColor, value: WPStyleGuide.darkGrey(), range: NSMakeRange(0, dotPosition.encodedOffset))
        return styledDomain
    }
}

// MARK: UITableViewDelegate

extension SiteCreationDomainsViewController {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selectedDomain: String
        switch indexPath.section {
        case Sections.suggestions.rawValue:
            if searchSuggestions.count > 0 {
                selectedDomain = searchSuggestions[indexPath.row]
            } else {
                selectedDomain = siteTitleSuggestions[indexPath.row]
            }
        default:
            return
        }

        tableView.deselectSelectedRowWithAnimation(true)
        let message = "'\(selectedDomain)' selected.\nThis is a work in progress. If you need to create a site, disable the siteCreation feature flag."
        let alertController = UIAlertController(title: nil,
                                                message: message,
                                                preferredStyle: .alert)
        alertController.addDefaultActionWithTitle("OK")
        self.present(alertController, animated: true, completion: nil)
    }
}

// MARK: SiteCreationDomainSearchTableViewCellDelegate

extension SiteCreationDomainsViewController: SiteCreationDomainSearchTableViewCellDelegate {
    func startSearch(for searchTerm: String) {
        guard searchTerm.count > 0 else {
            searchSuggestions = []
            tableView.reloadSections(IndexSet(integer: Sections.suggestions.rawValue), with: .automatic)
            return
        }

        suggestDomains(for: searchTerm) { [weak self] (suggestions) in
            self?.searchSuggestions = suggestions
            self?.tableView.reloadSections(IndexSet(integer: Sections.suggestions.rawValue), with: .automatic)
        }
    }
}
