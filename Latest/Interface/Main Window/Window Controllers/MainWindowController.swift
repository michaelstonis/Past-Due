//
//  MainWindowController.swift
//  Latest
//
//  Created by Max Langer on 27.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa

/**
 This class controls the main window of the app. It includes the list of apps that have an update available as well as the release notes for the specific update.
 */
class MainWindowController: NSWindowController, NSMenuItemValidation, NSMenuDelegate, UpdateCheckProgressReporting {
    
	/// Encapsulates the main window items with their according tag identifiers
	private enum MainMenuItem: Int {
		case latest = 0, file, edit, view, window, help
	}
    
    /// The list view holding the apps
    lazy var listViewController : UpdateTableViewController = {
		let splitViewController = self.contentViewController as? NSSplitViewController
        guard let firstItem = splitViewController?.splitViewItems[0], let controller = firstItem.viewController as? UpdateTableViewController else {
                return UpdateTableViewController()
        }
		
		// Override sidebar collapsing behavior
		firstItem.canCollapse = false
        
        return controller
    }()
    
    /// The detail view controller holding the release notes
    lazy var releaseNotesViewController : ReleaseNotesViewController = {
        guard let splitViewController = self.contentViewController as? NSSplitViewController,
            let secondItem = splitViewController.splitViewItems[1].viewController as? ReleaseNotesViewController else {
                return ReleaseNotesViewController()
        }
        
        return secondItem
    }()
    
    /// The progress indicator showing that an update check is in progress.
	lazy var progressIndicator: NSProgressIndicator = {
		let progressIndicator = NSProgressIndicator()
		progressIndicator.controlSize = .small
		progressIndicator.style = .spinning
		progressIndicator.isIndeterminate = true
		progressIndicator.isDisplayedWhenStopped = false
		progressIndicator.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			progressIndicator.widthAnchor.constraint(equalToConstant: 16),
			progressIndicator.heightAnchor.constraint(equalToConstant: 16)
		])
		
		return progressIndicator
	}()
	
	/// The toolbar item hosting `progressIndicator`, hidden when idle so it takes no space in the toolbar.
	weak var progressIndicatorToolbarItem: NSToolbarItem?
    
	/// The button that triggers an reload/recheck for updates
    @IBOutlet weak var reloadTouchBarButton: NSButton!

	private var presentedObservationFailures = Set<String>()
    
    override func windowDidLoad() {
        super.windowDidLoad()
    
		self.window?.titlebarAppearsTransparent = true
		self.window?.title = (Bundle.main.localizedInfoDictionary?[kCFBundleNameKey as String] ?? Bundle.main.infoDictionary?[kCFBundleNameKey as String]) as? String ?? "Past Due"
		self.window?.toolbarStyle = .unified
		
		// Set ourselves as the view menu delegate
		NSApplication.shared.mainMenu?.item(at: MainMenuItem.view.rawValue)?.submenu?.delegate = self
		self.installExportMenuItemIfNeeded()
		
		UpdateCheckCoordinator.shared.progressDelegate = self
        
        self.window?.makeFirstResponder(self.listViewController)
        self.window?.delegate = self
        
        self.listViewController.checkForUpdates()
        self.listViewController.releaseNotesViewController = self.releaseNotesViewController

        if let splitViewController = self.contentViewController as? NSSplitViewController {
			splitViewController.splitView.autosaveName = "MainSplitView"
			
            let detailItem = splitViewController.splitViewItems[1]
            detailItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings
        }
    }

    
    // MARK: - Action Methods
    
    /// Reloads the list / checks for updates
    @IBAction func reload(_ sender: Any?) {
        self.listViewController.checkForUpdates()
    }
    
    /// Open all apps that have an update available. If apps from the Mac App Store are there as well, open the Mac App Store
    @IBAction func updateAll(_ sender: Any?) {
		let apps = UpdateCheckCoordinator.shared.appProvider.updatableApps
		
		// Check if there are app store updates
		if apps.contains(where: { $0.bundle.source == .appStore }) {
			do {
				try AppStoreUpdateOperation.prepareForUpdates()
			} catch {
				let updatesPage = URL(string: "macappstore://apps.apple.com/updates")!
				if !AppStoreUpdateSettings.alwaysPerformManualUpdates.active {
					UpdateInstallHelperAlert.present(with: error, fallbackURL: updatesPage)
				} else {
					NSWorkspace.shared.open(updatesPage)
				}
			}
		}
		
		// Iterate all updatable apps and perform update
		apps.forEach({ app in
			if !app.isUpdating {
				app.performUpdate(isBulkUpdate: true)
			}
		})
    }
    	
	@IBAction func performFindPanelAction(_ sender: Any?) {
		self.window?.makeFirstResponder(self.listViewController.searchField)
	}
    
	@IBAction func visitWebsite(_ sender: NSMenuItem?) {
		NSWorkspace.shared.open(URL(string: "https://github.com/michaelstonis/Past-Due")!)
    }
	
	@IBAction func donate(_ sender: NSMenuItem?) {
		NSWorkspace.shared.open(URL(string: "https://max.codes/latest/donate/")!)
	}
    
	fileprivate func validate(_ selector: Selector) -> Bool {
		switch selector {
		case #selector(updateAll(_:)):
			hasUpdatesAvailable
		case #selector(reload(_:)):
			!isRunningUpdateCheck
		default:
			true
		}
	}
	
    
    // MARK: Menu Item

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else {
            return true
        }
        
        switch action {
		// Only allow the find item
		case #selector(performFindPanelAction(_:)):
			return menuItem.tag == 1
        default:
            return validate(action)
        }
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.forEach { (menuItem) in
			// Sort By menu constructed dynamically
			if menuItem.identifier == NSUserInterfaceItemIdentifier(rawValue: "sortByMenu") {
				menuItem.submenu?.items = sortByMenuItems
			}

            guard let action = menuItem.action else { return }
            
            switch action {
			case #selector(toggleShowInstalledUpdates(_:)):
                menuItem.state = AppListSettings.shared.showInstalledUpdates ? .on : .off
			case #selector(toggleShowIgnoredUpdates(_:)):
                menuItem.state = AppListSettings.shared.showIgnoredUpdates ? .on : .off
            default:
                ()
            }
		}
    }
	
	private var sortByMenuItems: [NSMenuItem] {
		AppListSettings.SortOptions.allCases.map { order in
			let item = NSMenuItem(title: order.displayName, action: #selector(changeSortOrder), keyEquivalent: "")
			item.representedObject = order
			item.state = AppListSettings.shared.sortOrder == order ? .on : .off
			
			return item
		}
	}
    
    
    // MARK: - Update Checker Progress Delegate
	
	func updateCheckerDidStartScanningForApps(_ updateChecker: UpdateCheckCoordinator) {
		self.isRunningUpdateCheck = true
		self.window?.toolbar?.validateVisibleItems()
	}
    
    /// This implementation activates the progress indicator and disables the reload button
	func updateChecker(_ updateChecker: UpdateCheckCoordinator, didStartCheckingApps numberOfApps: Int) {
		self.isRunningUpdateCheck = true
	}
    
    /// Update the progress indicator
	func updateChecker(_ updateChecker: UpdateCheckCoordinator, didCheckApp: App) {
		// Indeterminate spinner remains active until checking finishes
    }
	
	func updateCheckerDidFinishCheckingForUpdates(_ updateChecker: UpdateCheckCoordinator) {
		self.isRunningUpdateCheck = false
		self.window?.toolbar?.validateVisibleItems()
	}

	func updateChecker(_ updateChecker: UpdateCheckCoordinator, didFailToObserveDirectoryAt url: URL, error: Error) {
		let failureKey = "\(url.path)|\(error.localizedDescription)"
		guard presentedObservationFailures.insert(failureKey).inserted else { return }
		NSApplication.shared.requestUserAttention(.informationalRequest)
		
		guard let window = self.window else { return }
		
		let alert = NSAlert()
		alert.alertStyle = .warning
		alert.messageText = NSLocalizedString("DirectoryObservationFailedAlertTitle", comment: "Title of alert shown when Past Due cannot monitor a configured app scan directory.")
		alert.informativeText = self.directoryObservationFailureMessage(for: url, error: error)
		alert.addButton(withTitle: NSLocalizedString("OKAction", comment: "Default button for dismissing an informational alert."))
		alert.beginSheetModal(for: window)
	}
    
	
	// MARK: - Actions
	
	@IBAction func changeSortOrder(_ sender: NSMenuItem?) {
		AppListSettings.shared.sortOrder = sender?.representedObject as! AppListSettings.SortOptions
	}

	@IBAction func toggleShowInstalledUpdates(_ sender: NSMenuItem?) {
		AppListSettings.shared.showInstalledUpdates.toggle()
	}
	
	@IBAction func toggleShowIgnoredUpdates(_ sender: NSMenuItem?) {
		AppListSettings.shared.showIgnoredUpdates.toggle()
	}
	
	@IBAction func exportAppList(_ sender: Any?) {
		guard let window = self.window else { return }
		let savePanel = NSSavePanel()
		savePanel.title = NSLocalizedString("ExportAppListTitle", value: "Export Installed App List", comment: "Save panel title for exporting the installed app list.")
		savePanel.nameFieldStringValue = "Past-Due-Apps.json"
		savePanel.canCreateDirectories = true
		savePanel.isExtensionHidden = false
		
		savePanel.beginSheetModal(for: window) { response in
			guard response == .OK, let url = savePanel.url else { return }
			let format = AppInventoryExporter.Format.from(pathExtension: url.pathExtension)
			let apps = UpdateCheckCoordinator.shared.appProvider.allApps
			let content = AppInventoryExporter.export(apps: apps, format: format)
			try? content.data(using: .utf8)?.write(to: url, options: .atomic)
		}
	}
	
	private func installExportMenuItemIfNeeded() {
		guard let fileMenu = NSApplication.shared.mainMenu?.item(at: MainMenuItem.file.rawValue)?.submenu,
			  !fileMenu.items.contains(where: { $0.action == #selector(exportAppList(_:)) }) else {
			return
		}
		let exportItem = NSMenuItem(
			title: NSLocalizedString("ExportAppListMenuItem", value: "Export App List…", comment: "File menu item to export the list of installed apps."),
			action: #selector(exportAppList(_:)),
			keyEquivalent: "e"
		)
		exportItem.keyEquivalentModifierMask = [.command, .shift]
		fileMenu.addItem(NSMenuItem.separator())
		fileMenu.addItem(exportItem)
	}

	
	// MARK: - Accessors
	
	/// Whether there are any updatable apps.
	private var hasUpdatesAvailable: Bool {
		!UpdateCheckCoordinator.shared.appProvider.updatableApps.isEmpty
	}
	
	/// Whether an update check is currently running
	private(set) var isRunningUpdateCheck: Bool = false {
		didSet {
			self.reloadTouchBarButton?.isEnabled = !isRunningUpdateCheck
			self.progressIndicator.isHidden = !isRunningUpdateCheck
			self.progressIndicatorToolbarItem?.isHidden = !isRunningUpdateCheck
			if isRunningUpdateCheck {
				self.progressIndicator.startAnimation(nil)
			} else {
				self.progressIndicator.stopAnimation(nil)
			}
		}
	}

    
    // MARK: - Private Methods
    	
    private func showReleaseNotes(_ show: Bool, animated: Bool) {
        guard let splitViewController = self.contentViewController as? NSSplitViewController else {
            return
        }
        
        let detailItem = splitViewController.splitViewItems[1]
        
        if animated {
            detailItem.animator().isCollapsed = !show
        } else {
            detailItem.isCollapsed = !show
        }
        
        if !show {
            // Deselect current app
            self.listViewController.selectApp(at: nil)
        }
    }

	private func directoryObservationFailureMessage(for url: URL, error: Error) -> String {
		let format = NSLocalizedString("DirectoryObservationFailedAlertMessage", comment: "Alert text shown when Past Due cannot monitor a configured app scan directory. The first placeholder is the directory path, the second is the localized system error.")
		var message = String.localizedStringWithFormat(format, url.path, error.localizedDescription)
		
		let nsError = error as NSError
		if nsError.domain == NSPOSIXErrorDomain,
		   let code = POSIXErrorCode(rawValue: Int32(nsError.code)),
		   code == .EACCES || code == .EPERM {
			let recovery = NSLocalizedString("DirectoryObservationFailedPermissionSuggestion", comment: "Additional suggestion shown when the app likely lacks permission to observe a scan directory.")
			message += "\n\n\(recovery)"
		}
		
		return message
	}
	
}

extension MainWindowController: NSWindowDelegate {
	
	func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
		// Always position sheets at the top of the window, ignoring toolbar insets
		return NSRect(x: rect.minX, y: window.frame.height, width: rect.width, height: rect.height)
	}
    
}

extension MainWindowController: NSToolbarItemValidation {
	func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
		guard let action = item.action else { return true }
		return validate(action)
	}
}
