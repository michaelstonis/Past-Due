//
//  ViewController.swift
//  Latest
//
//  Created by Max Langer on 15.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa

/**
 This is the class handling the update process and displaying its results
 */
class UpdateTableViewController: NSViewController, NSMenuItemValidation, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, Observer {
	
	var id = UUID()
	
	private let snapshotQueue = DispatchQueue(label: "com.halfbuttonpress.PastDue.snapshot", qos: .userInitiated)
	private var snapshotGeneration: UInt64 = 0
	
    /// The array holding the apps that have an update available.
	var snapshot: AppListSnapshot = AppListSnapshot(withApps: [], filterQuery: nil) {
		didSet {
			self.updatePlaceholderVisibility()
		}
	}
	
	/// Convenience for accessing regular apps that should be displayed in the upper table.
	var apps: [AppListSnapshot.Entry] {
		return self.snapshot.entries
	}
	
	/// Convenience for accessing Homebrew packages displayed in the lower Homebrew table.
	var homebrewApps: [AppListSnapshot.Entry] {
		return self.snapshot.homebrewEntries
	}
	
	private static let homebrewSectionHeightDefaultsKey = "HomebrewSidebarSectionHeightKey"
	
	/// Upper Applications section header controls.
	private var applicationsHeaderView: NSView?
	private var applicationsCountLabel: NSTextField?
	private var applicationsCollapseButton: NSButton?
	private var isApplicationsSectionCollapsed = false
	
	/// Lower sidebar container and table view dedicated to Homebrew-managed Casks and Formulae.
	private var homebrewContainerView: NSView?
	private var homebrewTableView: UpdateTableView?
	private var homebrewCountLabel: NSTextField?
	private var homebrewCollapseButton: NSButton?
	private var homebrewCollapsedConstraint: NSLayoutConstraint?
	private var homebrewExpandedHeightConstraint: NSLayoutConstraint?
	private var homebrewCustomHeightConstraint: NSLayoutConstraint?
	private var homebrewFillWhenAppsCollapsedConstraint: NSLayoutConstraint?
	private var homebrewUserHeight: CGFloat? = {
		let saved = UserDefaults.standard.double(forKey: "HomebrewSidebarSectionHeightKey")
		return saved >= 90 ? CGFloat(saved) : nil
	}()
	private var dragStartHeight: CGFloat = 0
	private var isHomebrewSectionCollapsed = false
	        
    /// The detail view controller that shows the release notes
    weak var releaseNotesViewController : ReleaseNotesViewController?
    
    /// The empty state label centered in the list view indicating that no updates are available
    @IBOutlet weak var placeholderLabel: NSTextField!
	
	/// The label indicating how many updates are available
    @IBOutlet weak var updatesLabel: NSTextField!
        
    /// The menu displayed on secondary clicks on cells in the list
    @IBOutlet weak var tableViewMenu: NSMenu!
    
	/// Constraint controlling the top constraint of the table view.
	@IBOutlet weak var topTableConstraint: NSLayoutConstraint!
	
	/// The currently selected app within the UI.
	var selectedApp: App? {
		willSet {
			if let app = newValue, !self.snapshot.contains(app) {
				fatalError("Attempted to select app that is not available.")
			}
		}
	}

	/// The index of the currently selected app within the UI.
	var selectedAppIndex: Int? {
		if let app = self.selectedApp {
			return self.snapshot.index(of: app)
		}
		
		return nil
	}
	
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MLMUpdateCellIdentifier"), owner: self) {
            self.tableView.rowHeight = cell.frame.height
        }
                        
        self.tableViewMenu.delegate = self
        self.tableView.menu = self.tableViewMenu
		self.setupHomebrewSectionView()
		
		AppListSettings.shared.add(self, handler: self.updateSnapshot)
        
		UpdateCheckCoordinator.shared.appProvider.addObserver(self) { [weak self] newValue in
			guard let self else { return }
			self.snapshotGeneration &+= 1
			let generation = self.snapshotGeneration
			let query = self.snapshot.filterQuery
			self.snapshotQueue.async { [weak self] in
				let builtSnapshot = AppListSnapshot(withApps: newValue, filterQuery: query)
				DispatchQueue.main.async {
					guard let self, self.snapshotGeneration == generation else { return }
					self.scheduleTableViewUpdate(with: builtSnapshot, animated: true)
					self.updateTitleAndBatch()
				}
			}
		}
		
		self.updatesLabel.isHidden = true
		
		if #available(macOS 26, *) {
			self.tableView.enclosingScrollView?.scrollerInsets = .init(top: 0, left: 0, bottom: 10, right: 0)
		}
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
		
		// Setup title
		self.updateTitleAndBatch()
		
		// Setup search field
        NSLayoutConstraint(item: self.searchField!, attribute: .top, relatedBy: .equal, toItem: self.view.window?.contentLayoutGuide, attribute: .top, multiplier: 1.0, constant: 1).isActive = true
		self.view.window?.makeFirstResponder(nil)
	}
	
	deinit {
		AppListSettings.shared.remove(self)
	}
    
    
    // MARK: - TableView Stuff
    
    /// The table view displaying the list
    @IBOutlet weak var tableView: NSTableView!
    
	func updateSnapshot() {
		self.scheduleTableViewUpdate(with: self.snapshot.updated(), animated: true)
		self.updateTitleAndBatch()
	}
	
	
    // MARK: Table View Delegate
	
	private func isHomebrew(_ tableView: NSTableView) -> Bool {
		return tableView === self.homebrewTableView
	}
	
	private func entries(for tableView: NSTableView) -> [AppListSnapshot.Entry] {
		return isHomebrew(tableView) ? self.homebrewApps : self.apps
	}
	
	private func contentCell(for app: App, in tableView: NSTableView) -> NSView? {
        guard let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MLMUpdateCellIdentifier"), owner: self) as? UpdateCell else {
            return nil
        }
		
		// Only update image if needed, as this might result in flicker
		if cell.app != app {
			IconCache.shared.icon(for: app) { (image) in
				cell.imageView?.image = image
			}
		}

		cell.app = app
		cell.filterQuery = self.snapshot.filterQuery

        return cell
	}
	
	private func headerCell(of section: AppListSnapshot.Section, in tableView: NSTableView) -> NSView? {
		let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MLMUpdateCellSectionIdentifier"), owner: self) as? UpdateGroupCellView
		
		view?.section = section
		
		return view
	}
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let list = entries(for: tableView)
		guard row >= 0 && row < list.count else { return nil }
		
		switch list[row] {
		case .app(let app):
			return self.contentCell(for: app, in: tableView)
		case .section(let section):
			return self.headerCell(of: section, in: tableView)
		}
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		let inBrew = isHomebrew(tableView)
		let list = entries(for: tableView)
		guard row >= 0 && row < list.count else { return nil }
		
		if self.snapshot.isSectionHeader(at: row, inHomebrewSection: inBrew) {
			return UpdateGroupRowView()
		}
		
		return nil
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		let inBrew = isHomebrew(tableView)
		let list = entries(for: tableView)
		guard row >= 0 && row < list.count else { return -1 }
		return self.snapshot.isSectionHeader(at: row, inHomebrewSection: inBrew) ? 27 : 65
    }
    
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
		let inBrew = isHomebrew(tableView)
		let list = entries(for: tableView)
		guard row >= 0 && row < list.count else { return false }
        return self.snapshot.isSectionHeader(at: row, inHomebrewSection: inBrew)
    }
    
    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
		let inBrew = isHomebrew(tableView)
		let list = entries(for: tableView)
		guard row >= 0 && row < list.count else { return [] }

		// Prevent section headers from displaying row actions
		if self.snapshot.isSectionHeader(at: row, inHomebrewSection: inBrew) { return [] }
		
        if edge == .trailing {
			guard let app = self.snapshot.app(at: row, inHomebrewSection: inBrew) else { return [] }
			
			// Don't provide an update action if the app has no update available
			if !app.updateAvailable || app.isUpdating {
				return []
			}
			
            let action = NSTableViewRowAction(style: .regular, title: updateTitle(for: app), handler: { (action, row) in
                self.snapshot.app(at: row, inHomebrewSection: inBrew)?.performUpdate()
				tableView.rowActionsVisible = false
            })
			
			action.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
			action.backgroundColor = .systemCyan
			
            return [action]
        } else if edge == .leading {
			let open = NSTableViewRowAction(style: .regular, title: NSLocalizedString("OpenAction", comment: "Action to open a given app.")) { action, row in
				self.snapshot.app(at: row, inHomebrewSection: inBrew)?.open()
				tableView.rowActionsVisible = false
			}
			open.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
			
            let reveal = NSTableViewRowAction(style: .regular, title: NSLocalizedString("RevealAction", comment: "Revea in Finder Row action"), handler: { (action, row) in
                self.snapshot.app(at: row, inHomebrewSection: inBrew)?.showInFinder()
				tableView.rowActionsVisible = false
            })
			reveal.backgroundColor = .systemGray
			reveal.image = NSImage(systemSymbolName: "finder", accessibilityDescription: nil)
			
            return [open, reveal]
        }
        
        return []
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		let inBrew = isHomebrew(tableView)
		let list = entries(for: tableView)
		guard row >= 0 && row < list.count else { return false }

        return !self.snapshot.isSectionHeader(at: row, inHomebrewSection: inBrew)
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
		guard let changedTable = notification.object as? NSTableView else {
			self.selectApp(at: self.tableView.selectedRow)
			return
		}
		if isHomebrew(changedTable) {
			let row = changedTable.selectedRow
			guard row >= 0, let app = self.snapshot.app(at: row, inHomebrewSection: true) else {
				if self.tableView.selectedRow < 0 {
					self.selectApp(at: nil)
				}
				return
			}
			self.tableView.deselectAll(nil)
			self.selectedApp = app
			self.releaseNotesViewController?.display(releaseNotesFor: app)
		} else {
			if self.tableView.selectedRow >= 0 {
				self.homebrewTableView?.deselectAll(nil)
				self.selectApp(at: self.tableView.selectedRow)
			} else if (self.homebrewTableView?.selectedRow ?? -1) < 0 {
				self.selectApp(at: nil)
			}
		}
    }
    
    // MARK: Table View Data Source
    
    func numberOfRows(in tableView: NSTableView) -> Int {
		return entries(for: tableView).count
    }
	
	
	// MARK: Update Scheduling
	
	/// The next snapshot to be applied to the table view.
	private var newSnapshot: AppListSnapshot?
	
	/// Whether an table view update is already scheduled.
	private var tableViewUpdateScheduled = false
	
	/// Whether a table view update is currently ongoing.
	private var tableViewUpdateInProgress = false
	
	/// Schedules a table view update with the given snapshot.
	func scheduleTableViewUpdate(with snapshot: AppListSnapshot, animated: Bool) {
		self.newSnapshot = snapshot

		if self.tableViewUpdateInProgress {
			self.tableViewUpdateScheduled = true
			return
		}
				
		if animated {
			if self.tableViewUpdateScheduled {
				return
			}

			self.tableViewUpdateScheduled = true
			self.perform(#selector(updateTableViewAnimated), with: nil, afterDelay: 0.1)
			return
		}
		
		self.tableViewUpdateScheduled = false
		self.newSnapshot = nil
		self.snapshot = snapshot
		self.tableView.reloadData()
		self.reloadHomebrewSection()
		
		// Update selected app
		self.ensureSelection()
	}
	
	@objc func updateTableViewAnimated() {
		guard self.tableViewUpdateScheduled, let snapshot = newSnapshot else {
			return
		}
		self.tableViewUpdateScheduled = false
		self.tableViewUpdateInProgress = true
		
		let oldSnapshot = self.snapshot
		self.snapshot = snapshot
		self.newSnapshot = nil
		self.updateTableView(with: oldSnapshot, with: self.snapshot)
		self.reloadHomebrewSection()
		
		// Update selected app
		self.ensureSelection()
		
		self.tableViewUpdateInProgress = false
		self.updateTableViewAnimated()
	}
    
    
    // MARK: - Public Methods
    
    /// Triggers the update checking mechanism
    func checkForUpdates() {
		UpdateCheckCoordinator.shared.run()
		self.view.window?.makeFirstResponder(self)
    }

    /**
    Selects the app at the given index in the upper regular apps table.
     - parameter index: The index of the given app. If nil, the currently selected app is deselected.
     */
    func selectApp(at index: Int?) {
        guard let index = index, index >= 0, let app = self.snapshot.app(at: index) else {
			self.selectedApp = nil
            self.tableView.deselectAll(nil)
			self.homebrewTableView?.deselectAll(nil)
			self.scrubber?.animator().selectedIndex = -1
			
			// Clear release notes
			if let detailViewController = self.releaseNotesViewController {
				detailViewController.display(releaseNotesFor: nil)
			}
            
            return
        }
        
		self.homebrewTableView?.deselectAll(nil)
		if self.selectedApp?.identifier == app.identifier && index == self.tableView.selectedRow {
			if self.selectedApp !== app {
				self.selectedApp = app
				self.releaseNotesViewController?.display(releaseNotesFor: app)
			}
			return
		}
		
		self.scrubber?.animator().scrollItem(at: index, to: .center)
		self.scrubber?.animator().selectedIndex = index
        
        self.tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        self.tableView.scrollRowToVisible(index)
			
		self.selectedApp = app
		self.releaseNotesViewController?.display(releaseNotesFor: app)
    }
    
    
    // MARK: - Menu Item Stuff
	
	private func targetApp(forMenuItem menuItem: NSMenuItem?) -> App? {
		if let app = menuItem?.representedObject as? App {
			return app
		}
		if let selected = self.selectedApp {
			return selected
		}
		return self.app(at: self.tableView.selectedRow)
	}
    
    /// Open a single app
    @IBAction func updateApp(_ sender: NSMenuItem?) {
		guard let app = self.targetApp(forMenuItem: sender) else { return }
		DispatchQueue.main.async {
			app.performUpdate()
		}
    }
	
	@IBAction func ignoreApp(_ sender: NSMenuItem?) {
		guard let app = self.targetApp(forMenuItem: sender) else { return }
		UpdateCheckCoordinator.shared.appProvider.setIgnoredState(true, for: app)
	}
	
	@IBAction func unignoreApp(_ sender: NSMenuItem?) {
		guard let app = self.targetApp(forMenuItem: sender) else { return }
		UpdateCheckCoordinator.shared.appProvider.setIgnoredState(false, for: app)
	}
	
	@IBAction func skipVersion(_ sender: NSMenuItem?) {
		guard let app = self.targetApp(forMenuItem: sender), let remoteVersion = app.remoteVersion else { return }
		UpdateCheckCoordinator.shared.appProvider.setSkippedVersion(remoteVersion, for: app)
	}
	
	@IBAction func unskipVersion(_ sender: NSMenuItem?) {
		guard let app = self.targetApp(forMenuItem: sender) else { return }
		UpdateCheckCoordinator.shared.appProvider.setSkippedVersion(nil, for: app)
	}
	
	/// Opens the selected app
	@IBAction func openApp(_ sender: NSMenuItem?) {
		self.targetApp(forMenuItem: sender)?.open()
	}
    
    /// Show the bundle of an app in Finder
    @IBAction func showAppInFinder(_ sender: NSMenuItem?) {
        self.targetApp(forMenuItem: sender)?.showInFinder()
    }
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else {
            return true
        }
        
		guard let app = self.targetApp(forMenuItem: menuItem) else {
			return false
		}
		
		switch action {
		case #selector(updateApp(_:)):
			menuItem.title = updateTitle(for: app)
			return app.updateAvailable && !app.isUpdating
		case #selector(openApp(_:)), #selector(showAppInFinder(_:)):
            return true
		case #selector(ignoreApp(_:)):
			menuItem.isHidden = app.isIgnored
			return true
		case #selector(unignoreApp(_:)):
			menuItem.isHidden = !app.isIgnored
			return true
		case #selector(skipVersion(_:)):
			let canSkip = app.updateAvailable && !app.isIgnored && app.remoteVersion != nil
			menuItem.isHidden = !canSkip
			if let versionText = app.remoteVersion?.versionNumber ?? app.remoteVersion?.buildNumber {
				menuItem.title = String(format: NSLocalizedString("SkipVersionFormat", value: "Skip Version %@", comment: "Context menu item to skip a specific version until the next update"), versionText)
			} else {
				menuItem.title = NSLocalizedString("SkipVersionAction", value: "Skip This Version", comment: "Context menu item to skip the current version")
			}
			return canSkip
		case #selector(unskipVersion(_:)):
			let isSkipped = app.isCurrentUpdateSkipped
			menuItem.isHidden = !isSkipped
			return isSkipped
        default:
            ()
        }
		
		return false
    }
    
    // MARK: Delegate
    
    func menuNeedsUpdate(_ menu: NSMenu) {
		ensureSkipVersionMenuItems(in: menu)
		let brewRow = self.homebrewTableView?.clickedRow ?? -1
		if brewRow != -1, !self.snapshot.isSectionHeader(at: brewRow, inHomebrewSection: true) {
			let clickedApp = self.snapshot.app(at: brewRow, inHomebrewSection: true)
			menu.items.forEach({ $0.representedObject = clickedApp })
			return
		}
        let row = self.tableView.clickedRow
        guard row != -1, !self.snapshot.isSectionHeader(at: row) else {
			menu.items.forEach({ $0.representedObject = nil })
			return
		}
		menu.items.forEach({ $0.representedObject = self.snapshot.app(at: row) })
    }
	
	private func ensureSkipVersionMenuItems(in menu: NSMenu) {
		guard !menu.items.contains(where: { $0.action == #selector(skipVersion(_:)) }) else { return }
		let skipItem = NSMenuItem(
			title: NSLocalizedString("SkipVersionAction", value: "Skip This Version", comment: "Context menu item to skip the current version"),
			action: #selector(skipVersion(_:)),
			keyEquivalent: ""
		)
		skipItem.target = self
		let unskipItem = NSMenuItem(
			title: NSLocalizedString("UnskipVersionAction", value: "Unskip Version", comment: "Context menu item to restore a skipped update version"),
			action: #selector(unskipVersion(_:)),
			keyEquivalent: ""
		)
		unskipItem.target = self
		if let ignoreIndex = menu.items.firstIndex(where: { $0.action == #selector(ignoreApp(_:)) }) {
			menu.insertItem(unskipItem, at: ignoreIndex)
			menu.insertItem(skipItem, at: ignoreIndex)
		} else {
			menu.addItem(skipItem)
			menu.addItem(unskipItem)
		}
	}
    
	
	// MARK: - Search
	
	/// The search field used for filtering apps
	@IBOutlet weak var searchField: NSSearchField!
	
	
	// MARK: - Actions
	
    /// Updates the app at the given index.
    private func updateApp(atIndex index: Int) {
		guard let app = self.app(at: index) else { return }
		
		// Delay update to improve animations
        DispatchQueue.main.async {
			app.performUpdate()
        }
    }
	
	/// Sets the ignored state for the app at the given index
	private func setIgnored(_ ignored: Bool, forAppAt index: Int) {
		guard let app = self.app(at: index) else { return }
		UpdateCheckCoordinator.shared.appProvider.setIgnoredState(ignored, for: app)
	}
    
	/// Opens the app at a given index.
	private func openApp(at index: Int) {
		self.app(at: index)?.open()
	}
	
    /// Reveals the app at a given index in Finder
    private func showAppInFinder(at index: Int) {
		self.app(at: index)?.showInFinder()
    }
	
	/// Returns the app at the given index, if available.
	private func app(at index: Int) -> App? {
		guard index >= 0 && index < self.apps.count else {
			return nil
		}

		return self.snapshot.app(at: index)
	}
	
	
	// MARK: - Interface Updating
    
    /// Updates the UI depending on available updates (show empty states or update list)
    private func updatePlaceholderVisibility() {
		// Only show placeholder if there are no apps and also no active search (which might produce an empty list)
		let showPlaceholder = self.apps.isEmpty && self.homebrewApps.isEmpty && self.snapshot.filterQuery == nil
		
        if showPlaceholder && self.placeholderLabel.isHidden {
            self.tableView.isHidden = true
            self.placeholderLabel.isHidden = false
        } else if !showPlaceholder && !self.placeholderLabel.isHidden {
            self.tableView.isHidden = false
            self.placeholderLabel.isHidden = true
        }
    }
    
    /// Updates the title in the toolbar ("No / n updates available") and the badge of the app icon
    private func updateTitleAndBatch() {
		let showExternalUpdates = AppListSettings.shared.includeAppsWithLimitedSupport
		let showHomebrewUpdates = AppListSettings.shared.includeHomebrewUpdates
		let count = UpdateCheckCoordinator.shared.appProvider.countOfAvailableUpdates(where: {
			(showExternalUpdates || $0.usesBuiltInUpdater) && (showHomebrewUpdates || !$0.isManagedByHomebrew)
		})
		let statusText: String
		
		// Update dock badge
		NSApplication.shared.dockTile.badgeLabel = count == 0 ? nil : NumberFormatter().string(from: count as NSNumber)
		
		let format = NSLocalizedString("NumberOfUpdatesAvailable", comment: "number of updates available")
		statusText = String.localizedStringWithFormat(format, count)
        
		self.scrubber?.reloadData()
		self.view.window?.subtitle = statusText
	}
	
	private func ensureSelection() {
		if let app = self.selectedApp {
			if let regularIndex = self.snapshot.index(of: app) {
				self.selectApp(at: regularIndex)
				return
			}
			if let brewIndex = self.snapshot.homebrewIndex(of: app),
			   let updatedApp = self.snapshot.app(at: brewIndex, inHomebrewSection: true) {
				self.tableView.deselectAll(nil)
				self.homebrewTableView?.selectRowIndexes(IndexSet(integer: brewIndex), byExtendingSelection: false)
				self.selectedApp = updatedApp
				self.releaseNotesViewController?.display(releaseNotesFor: updatedApp)
				return
			}
		}
		self.selectApp(at: nil)
	}
	
	// MARK: - Split Sidebar Panes (Upper Applications + Resizable Lower Homebrew)
	
	private func setupHomebrewSectionView() {
		guard let upperScrollView = self.tableView.enclosingScrollView else { return }
		
		// 1. Upper "Applications" Header Bar
		let appsHeader = NSVisualEffectView()
		appsHeader.material = .sidebar
		appsHeader.blendingMode = .withinWindow
		appsHeader.translatesAutoresizingMaskIntoConstraints = false
		self.view.addSubview(appsHeader)
		self.applicationsHeaderView = appsHeader
		
		let appsTopSeparator = NSBox()
		appsTopSeparator.boxType = .separator
		appsTopSeparator.translatesAutoresizingMaskIntoConstraints = false
		appsHeader.addSubview(appsTopSeparator)
		
		let appsDisclosure = NSButton()
		appsDisclosure.bezelStyle = .disclosure
		appsDisclosure.setButtonType(.pushOnPushOff)
		appsDisclosure.title = ""
		appsDisclosure.state = .on
		appsDisclosure.target = self
		appsDisclosure.action = #selector(toggleApplicationsSectionCollapsed(_:))
		appsDisclosure.translatesAutoresizingMaskIntoConstraints = false
		appsHeader.addSubview(appsDisclosure)
		self.applicationsCollapseButton = appsDisclosure
		
		let appsIconView = NSImageView()
		appsIconView.translatesAutoresizingMaskIntoConstraints = false
		if let symbol = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "Applications") {
			appsIconView.image = symbol
			appsIconView.contentTintColor = .secondaryLabelColor
		}
		appsHeader.addSubview(appsIconView)
		
		let appsTitleButton = NSButton(
			title: NSLocalizedString("ApplicationsSectionHeaderTitle", value: "Applications", comment: "Upper sidebar section title for regular macOS applications"),
			target: self,
			action: #selector(toggleApplicationsSectionCollapsed(_:))
		)
		appsTitleButton.isBordered = false
		appsTitleButton.font = .systemFont(ofSize: 12, weight: .semibold)
		appsTitleButton.contentTintColor = .secondaryLabelColor
		appsTitleButton.alignment = .left
		appsTitleButton.translatesAutoresizingMaskIntoConstraints = false
		appsHeader.addSubview(appsTitleButton)
		
		let appsCountLabel = NSTextField(labelWithString: "")
		appsCountLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
		appsCountLabel.textColor = .secondaryLabelColor
		appsCountLabel.alignment = .right
		appsCountLabel.translatesAutoresizingMaskIntoConstraints = false
		appsHeader.addSubview(appsCountLabel)
		self.applicationsCountLabel = appsCountLabel
		
		let appsBottomSeparator = NSBox()
		appsBottomSeparator.boxType = .separator
		appsBottomSeparator.translatesAutoresizingMaskIntoConstraints = false
		appsHeader.addSubview(appsBottomSeparator)
		
		// Deactivate Storyboard top & bottom constraints on upperScrollView so it sits between appsHeader and homebrewContainerView
		self.topTableConstraint?.isActive = false
		for constraint in self.view.constraints {
			if (constraint.firstItem as? NSView === upperScrollView && (constraint.firstAttribute == .bottom || constraint.firstAttribute == .top)) ||
			   (constraint.secondItem as? NSView === upperScrollView && (constraint.secondAttribute == .bottom || constraint.secondAttribute == .top)) {
				constraint.isActive = false
			}
		}
		
		// 2. Lower "Homebrew" Container & Draggable Header Bar
		let container = NSView()
		container.translatesAutoresizingMaskIntoConstraints = false
		container.wantsLayer = true
		self.view.addSubview(container)
		self.homebrewContainerView = container
		
		// Top separator line
		let separator = NSBox()
		separator.boxType = .separator
		separator.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(separator)
		
		// Draggable header bar for resizing the Homebrew section vertically
		let headerView = ResizableSidebarHeaderView()
		headerView.material = .sidebar
		headerView.blendingMode = .withinWindow
		headerView.translatesAutoresizingMaskIntoConstraints = false
		headerView.onDragBegan = { [weak self] in
			guard let self, let container = self.homebrewContainerView else { return }
			self.dragStartHeight = self.isHomebrewSectionCollapsed ? 31 : container.frame.height
		}
		headerView.onDragDelta = { [weak self] deltaY in
			self?.handleHomebrewHeaderDrag(deltaY: deltaY)
		}
		headerView.onClickWithoutDrag = { [weak self] in
			self?.toggleHomebrewSectionCollapsed(nil)
		}
		container.addSubview(headerView)
		
		let disclosureButton = NSButton()
		disclosureButton.bezelStyle = .disclosure
		disclosureButton.setButtonType(.pushOnPushOff)
		disclosureButton.title = ""
		disclosureButton.state = .on
		disclosureButton.target = self
		disclosureButton.action = #selector(toggleHomebrewSectionCollapsed(_:))
		disclosureButton.translatesAutoresizingMaskIntoConstraints = false
		headerView.addSubview(disclosureButton)
		self.homebrewCollapseButton = disclosureButton
		
		let iconView = NSImageView()
		iconView.translatesAutoresizingMaskIntoConstraints = false
		if let symbol = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "Homebrew") {
			iconView.image = symbol
			iconView.contentTintColor = .secondaryLabelColor
		}
		headerView.addSubview(iconView)
		
		let titleButton = NSTextField(labelWithString: NSLocalizedString("HomebrewSectionHeaderTitle", value: "Homebrew", comment: "Lower sidebar section title for Homebrew packages"))
		titleButton.font = .systemFont(ofSize: 12, weight: .semibold)
		titleButton.textColor = .secondaryLabelColor
		titleButton.alignment = .left
		titleButton.translatesAutoresizingMaskIntoConstraints = false
		headerView.addSubview(titleButton)
		
		let countLabel = NSTextField(labelWithString: "")
		countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
		countLabel.textColor = .secondaryLabelColor
		countLabel.alignment = .right
		countLabel.translatesAutoresizingMaskIntoConstraints = false
		headerView.addSubview(countLabel)
		self.homebrewCountLabel = countLabel
		
		let headerBottomSeparator = NSBox()
		headerBottomSeparator.boxType = .separator
		headerBottomSeparator.translatesAutoresizingMaskIntoConstraints = false
		headerView.addSubview(headerBottomSeparator)
		
		// Lower ScrollView + UpdateTableView
		let brewScrollView = NSScrollView()
		brewScrollView.drawsBackground = false
		brewScrollView.hasVerticalScroller = true
		brewScrollView.autohidesScrollers = true
		brewScrollView.borderType = .noBorder
		brewScrollView.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(brewScrollView)
		
		let brewTable = UpdateTableView()
		brewTable.headerView = nil
		brewTable.backgroundColor = .clear
		brewTable.rowHeight = self.tableView.rowHeight
		brewTable.intercellSpacing = self.tableView.intercellSpacing
		brewTable.selectionHighlightStyle = self.tableView.selectionHighlightStyle
		if #available(macOS 11.0, *) {
			brewTable.style = self.tableView.style
		}
		let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("HomebrewColumn"))
		col.resizingMask = .autoresizingMask
		brewTable.addTableColumn(col)
		brewTable.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
		
		// Register cell nibs copied from the primary Storyboard tableView
		if let registeredNibs = self.tableView.registeredNibsByIdentifier {
			for (identifier, nib) in registeredNibs {
				brewTable.register(nib, forIdentifier: identifier)
			}
		}
		
		brewTable.delegate = self
		brewTable.dataSource = self
		brewTable.menu = self.tableViewMenu
		brewScrollView.documentView = brewTable
		self.homebrewTableView = brewTable
		
		let collapsedHeight = container.heightAnchor.constraint(equalToConstant: 0)
		collapsedHeight.priority = .defaultHigh
		self.homebrewCollapsedConstraint = collapsedHeight
		
		let expandedHeight = container.heightAnchor.constraint(equalTo: self.view.heightAnchor, multiplier: 0.42)
		expandedHeight.priority = NSLayoutConstraint.Priority(730)
		self.homebrewExpandedHeightConstraint = expandedHeight
		
		let customHeight = container.heightAnchor.constraint(equalToConstant: self.homebrewUserHeight ?? 240)
		customHeight.priority = NSLayoutConstraint.Priority(745)
		self.homebrewCustomHeightConstraint = customHeight
		
		let fillWhenAppsCollapsed = container.topAnchor.constraint(equalTo: appsHeader.bottomAnchor)
		fillWhenAppsCollapsed.priority = NSLayoutConstraint.Priority(760)
		self.homebrewFillWhenAppsCollapsedConstraint = fillWhenAppsCollapsed
		
		let upperScrollBottom = upperScrollView.bottomAnchor.constraint(equalTo: container.topAnchor)
		upperScrollBottom.priority = NSLayoutConstraint.Priority(750)
		
		NSLayoutConstraint.activate([
			// Upper Applications Header Bar
			appsHeader.topAnchor.constraint(equalTo: self.searchField.bottomAnchor, constant: 8),
			appsHeader.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
			appsHeader.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
			appsHeader.heightAnchor.constraint(equalToConstant: 30),
			
			appsTopSeparator.topAnchor.constraint(equalTo: appsHeader.topAnchor),
			appsTopSeparator.leadingAnchor.constraint(equalTo: appsHeader.leadingAnchor),
			appsTopSeparator.trailingAnchor.constraint(equalTo: appsHeader.trailingAnchor),
			
			appsDisclosure.leadingAnchor.constraint(equalTo: appsHeader.leadingAnchor, constant: 10),
			appsDisclosure.centerYAnchor.constraint(equalTo: appsHeader.centerYAnchor),
			
			appsIconView.leadingAnchor.constraint(equalTo: appsDisclosure.trailingAnchor, constant: 4),
			appsIconView.centerYAnchor.constraint(equalTo: appsHeader.centerYAnchor),
			appsIconView.widthAnchor.constraint(equalToConstant: 14),
			appsIconView.heightAnchor.constraint(equalToConstant: 14),
			
			appsTitleButton.leadingAnchor.constraint(equalTo: appsIconView.trailingAnchor, constant: 5),
			appsTitleButton.centerYAnchor.constraint(equalTo: appsHeader.centerYAnchor),
			
			appsCountLabel.leadingAnchor.constraint(greaterThanOrEqualTo: appsTitleButton.trailingAnchor, constant: 8),
			appsCountLabel.trailingAnchor.constraint(equalTo: appsHeader.trailingAnchor, constant: -14),
			appsCountLabel.centerYAnchor.constraint(equalTo: appsHeader.centerYAnchor),
			
			appsBottomSeparator.bottomAnchor.constraint(equalTo: appsHeader.bottomAnchor),
			appsBottomSeparator.leadingAnchor.constraint(equalTo: appsHeader.leadingAnchor),
			appsBottomSeparator.trailingAnchor.constraint(equalTo: appsHeader.trailingAnchor),
			
			// Upper ScrollView between Applications Header and Lower Homebrew Container
			upperScrollView.topAnchor.constraint(equalTo: appsHeader.bottomAnchor),
			upperScrollBottom,
			
			// Lower Homebrew Container
			container.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
			container.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
			container.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
			collapsedHeight,
			
			separator.topAnchor.constraint(equalTo: container.topAnchor),
			separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			
			headerView.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
			headerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			headerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			headerView.heightAnchor.constraint(equalToConstant: 30),
			
			disclosureButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 10),
			disclosureButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
			
			iconView.leadingAnchor.constraint(equalTo: disclosureButton.trailingAnchor, constant: 4),
			iconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 14),
			iconView.heightAnchor.constraint(equalToConstant: 14),
			
			titleButton.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 5),
			titleButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
			
			countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleButton.trailingAnchor, constant: 8),
			countLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -14),
			countLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
			
			headerBottomSeparator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
			headerBottomSeparator.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
			headerBottomSeparator.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
			
			brewScrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
			brewScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			brewScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			brewScrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
		])
		
		container.isHidden = true
	}
	
	private func reloadHomebrewSection() {
		// Update upper Applications header badge
		let regUpdates = self.snapshot.regularAvailableUpdateCount
		let totalRegularApps = self.apps.reduce(0) { count, entry in
			if case .app = entry { return count + 1 }
			return count
		}
		if regUpdates > 0 {
			self.applicationsCountLabel?.stringValue = String.localizedStringWithFormat(
				NSLocalizedString("RegularUpdateCountBadge", value: "%d update(s)", comment: "Badge count in the Applications upper sidebar header"),
				regUpdates
			)
		} else {
			self.applicationsCountLabel?.stringValue = totalRegularApps > 0 ? "\(totalRegularApps)" : ""
		}
		self.tableView.enclosingScrollView?.isHidden = self.isApplicationsSectionCollapsed
		
		guard let container = self.homebrewContainerView,
			  let brewTable = self.homebrewTableView else { return }
		
		brewTable.reloadData()
		
		let hasHomebrewEntries = !self.homebrewApps.isEmpty
		if !hasHomebrewEntries {
			container.isHidden = true
			self.homebrewFillWhenAppsCollapsedConstraint?.isActive = false
			self.homebrewCustomHeightConstraint?.isActive = false
			self.homebrewExpandedHeightConstraint?.isActive = false
			self.homebrewCollapsedConstraint?.constant = 0
			self.homebrewCollapsedConstraint?.isActive = true
			return
		}
		
		container.isHidden = false
		let updateCount = self.snapshot.homebrewAvailableUpdateCount
		let totalPackages = self.homebrewApps.reduce(0) { count, entry in
			if case .app = entry { return count + 1 }
			return count
		}
		if updateCount > 0 {
			self.homebrewCountLabel?.stringValue = String.localizedStringWithFormat(
				NSLocalizedString("HomebrewUpdateCountBadge", value: "%d update(s)", comment: "Badge count in the Homebrew lower sidebar header"),
				updateCount
			)
		} else {
			self.homebrewCountLabel?.stringValue = "\(totalPackages)"
		}
		
		if self.isHomebrewSectionCollapsed {
			self.homebrewFillWhenAppsCollapsedConstraint?.isActive = false
			self.homebrewCustomHeightConstraint?.isActive = false
			self.homebrewExpandedHeightConstraint?.isActive = false
			self.homebrewCollapsedConstraint?.constant = 31
			self.homebrewCollapsedConstraint?.isActive = true
		} else if self.isApplicationsSectionCollapsed {
			self.homebrewCollapsedConstraint?.isActive = false
			self.homebrewCustomHeightConstraint?.isActive = false
			self.homebrewExpandedHeightConstraint?.isActive = false
			self.homebrewFillWhenAppsCollapsedConstraint?.isActive = true
		} else {
			self.homebrewFillWhenAppsCollapsedConstraint?.isActive = false
			self.homebrewCollapsedConstraint?.isActive = false
			if let userHeight = self.homebrewUserHeight {
				let maxAllowed = max(120, self.view.bounds.height - 170)
				let clamped = min(max(userHeight, 95), maxAllowed)
				self.homebrewExpandedHeightConstraint?.isActive = false
				self.homebrewCustomHeightConstraint?.constant = clamped
				self.homebrewCustomHeightConstraint?.isActive = true
			} else {
				self.homebrewCustomHeightConstraint?.isActive = false
				self.homebrewExpandedHeightConstraint?.isActive = true
			}
		}
	}
	
	private func handleHomebrewHeaderDrag(deltaY: CGFloat) {
		let proposedHeight = self.dragStartHeight + deltaY
		let totalHeight = self.view.bounds.height
		let appsHeaderBottom: CGFloat = 108 // searchField + Applications header
		let maxAllowed = max(120, totalHeight - appsHeaderBottom - 80)
		
		if self.isApplicationsSectionCollapsed {
			self.isApplicationsSectionCollapsed = false
			self.applicationsCollapseButton?.state = .on
		}
		
		if proposedHeight < 55 {
			// Snap to collapsed when dragged near the bottom
			if !self.isHomebrewSectionCollapsed {
				self.isHomebrewSectionCollapsed = true
				self.homebrewCollapseButton?.state = .off
				self.reloadHomebrewSection()
				self.view.layoutSubtreeIfNeeded()
			}
			return
		}
		
		if self.isHomebrewSectionCollapsed {
			self.isHomebrewSectionCollapsed = false
			self.homebrewCollapseButton?.state = .on
		}
		
		let clampedHeight = min(max(proposedHeight, 95), maxAllowed)
		self.homebrewUserHeight = clampedHeight
		UserDefaults.standard.set(Double(clampedHeight), forKey: Self.homebrewSectionHeightDefaultsKey)
		self.reloadHomebrewSection()
		self.view.layoutSubtreeIfNeeded()
	}
	
	@objc private func toggleApplicationsSectionCollapsed(_ sender: Any?) {
		self.isApplicationsSectionCollapsed.toggle()
		self.applicationsCollapseButton?.state = self.isApplicationsSectionCollapsed ? .off : .on
		if self.isApplicationsSectionCollapsed && self.isHomebrewSectionCollapsed && !self.homebrewApps.isEmpty {
			self.isHomebrewSectionCollapsed = false
			self.homebrewCollapseButton?.state = .on
		}
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.2
			context.allowsImplicitAnimation = true
			self.reloadHomebrewSection()
			self.view.layoutSubtreeIfNeeded()
		}
	}
	
	@objc private func toggleHomebrewSectionCollapsed(_ sender: Any?) {
		self.isHomebrewSectionCollapsed.toggle()
		self.homebrewCollapseButton?.state = self.isHomebrewSectionCollapsed ? .off : .on
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.2
			context.allowsImplicitAnimation = true
			self.reloadHomebrewSection()
			self.view.layoutSubtreeIfNeeded()
		}
	}
	
	/// Animates changes made to the apps list
	private func updateTableView(with oldSnapshot: AppListSnapshot, with newSnapshot: AppListSnapshot) {
		let oldValue = oldSnapshot.entries
		let newValue = newSnapshot.entries
		
		self.tableView.beginUpdates()
		
		var state = oldValue
		var i = 0, j = 0
		
		// Iterate both states
		while i < state.count || j < newValue.count {
			// Remove deleted elements
			if i < state.count && !newValue.contains(where: { $0.isSimilar(to: state[i]) }) {
				self.tableView.removeRows(at: IndexSet(integer: i), withAnimation: [.slideUp, .effectFade])
				state.remove(at: i)
				continue
			}
			
			// Skip identical/similar items at the same position and reload their content
			if i < state.count && j < newValue.count && state[i].isSimilar(to: newValue[j]) {
				state[i] = newValue[j]
				self.tableView.reloadData(forRowIndexes: IndexSet(integer: i), columnIndexes: IndexSet(integer: 0))
				i += 1
				j += 1
				continue
			}
			
			// Move existing elements
			if j < newValue.count, let index = state.firstIndex(where: { $0.isSimilar(to: newValue[j]) }) {
				let newIndex = i - (index < i ? 1 : 0)
				self.tableView.moveRow(at: index, to: newIndex)
				
				state.remove(at: index)
				state.insert(newValue[j], at: newIndex)
				self.tableView.reloadData(forRowIndexes: IndexSet(integer: newIndex), columnIndexes: IndexSet(integer: 0))
				
				i += 1
				j += 1
				continue
			}
			
			// Insert new elements
			if j < newValue.count {
				self.tableView.insertRows(at: IndexSet(integer: i), withAnimation: [.slideDown, .effectFade])
				state.insert(newValue[j], at: i)
				
				i += 1
				j += 1
			}
		}
		
		self.tableView.endUpdates()
	}
	
	/// Returns an appropriate title for update actions for the given app.
	private func updateTitle(for app: App) -> String {
		if let externalUpdater = app.externalUpdaterName {
			String(format: NSLocalizedString("ExternalUpdateAction", comment: "Action to update a given app outside of Latest. The placeholder is filled with the name of the external updater. (App Store, App Name)"), externalUpdater)
		} else {
			NSLocalizedString("UpdateAction", comment: "Action to update a given app.")
		}
	}
    
}

/// Sidebar section header view that supports vertical drag-to-resize as well as click-to-toggle-collapse.
private final class ResizableSidebarHeaderView: NSVisualEffectView {
	var onDragBegan: (() -> Void)?
	var onDragDelta: ((CGFloat) -> Void)?
	var onClickWithoutDrag: (() -> Void)?
	
	private var dragStartScreenY: CGFloat = 0
	private var isDraggingHeader = false
	
	override func resetCursorRects() {
		super.resetCursorRects()
		// Exclude the leading disclosure button area so the disclosure button keeps the standard arrow cursor
		let resizeRect = NSRect(x: 28, y: 0, width: max(0, bounds.width - 28), height: bounds.height)
		addCursorRect(resizeRect, cursor: .resizeUpDown)
	}
	
	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		// Draw a subtle centered grab handle pill near the top edge of the header bar
		let pillWidth: CGFloat = 28
		let pillHeight: CGFloat = 3
		let pillRect = NSRect(
			x: (bounds.width - pillWidth) / 2.0,
			y: bounds.height - pillHeight - 2.5,
			width: pillWidth,
			height: pillHeight
		)
		let path = NSBezierPath(roundedRect: pillRect, xRadius: 1.5, yRadius: 1.5)
		NSColor.tertiaryLabelColor.withAlphaComponent(0.45).setFill()
		path.fill()
	}
	
	override func mouseDown(with event: NSEvent) {
		let pointInWindow = event.locationInWindow
		if let window = self.window {
			dragStartScreenY = window.convertPoint(toScreen: pointInWindow).y
		} else {
			dragStartScreenY = pointInWindow.y
		}
		isDraggingHeader = false
		onDragBegan?()
	}
	
	override func mouseDragged(with event: NSEvent) {
		let currentY: CGFloat
		if let window = self.window {
			currentY = window.convertPoint(toScreen: event.locationInWindow).y
		} else {
			currentY = event.locationInWindow.y
		}
		let deltaY = currentY - dragStartScreenY
		if !isDraggingHeader && abs(deltaY) > 2 {
			isDraggingHeader = true
			NSCursor.resizeUpDown.push()
		}
		if isDraggingHeader {
			onDragDelta?(deltaY)
		}
	}
	
	override func mouseUp(with event: NSEvent) {
		if isDraggingHeader {
			NSCursor.pop()
			isDraggingHeader = false
		} else {
			onClickWithoutDrag?()
		}
	}
}
