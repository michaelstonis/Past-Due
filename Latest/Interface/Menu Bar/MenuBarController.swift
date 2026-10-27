//
//  MenuBarController.swift
//  Latest
//
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit

/// Manages the optional macOS Menu Bar status item (`NSStatusItem`) showing the available update count.
final class MenuBarController: NSObject, NSMenuDelegate, Observer {
	
	static let shared = MenuBarController()
	
	let id = UUID()
	
	/// Handler invoked when the user chooses to open the main Past Due window from the menu bar.
	var showMainWindowHandler: (() -> Void)?
	
	private var statusItem: NSStatusItem?
	private let menu = NSMenu()
	private var isStarted = false
	
	/// Initializes and starts observing settings and update state.
	func start() {
		guard !isStarted else { return }
		isStarted = true
		
		menu.delegate = self
		
		BackgroundCheckSettings.shared.add(self) { [weak self] in
			self?.updateStatusItemVisibility()
		}
		AppListSettings.shared.add(self) { [weak self] in
			self?.updateBadgeCount()
		}
		UpdateCheckCoordinator.shared.appProvider.addObserver(self) { [weak self] _ in
			self?.updateBadgeCount()
		}
		
		updateStatusItemVisibility()
	}
	
	private func updateStatusItemVisibility() {
		if BackgroundCheckSettings.shared.showMenuBarExtra {
			if statusItem == nil {
				let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
				item.menu = menu
				if let button = item.button {
					let image = NSImage(systemSymbolName: "arrow.down.app", accessibilityDescription: NSLocalizedString("MenuBarAccessibilityLabel", value: "Past Due Updates", comment: "Accessibility description for the Past Due menu bar icon."))
					image?.isTemplate = true
					button.image = image
					button.imagePosition = .imageLeading
				}
				statusItem = item
			}
			updateBadgeCount()
		} else if let item = statusItem {
			NSStatusBar.system.removeStatusItem(item)
			statusItem = nil
		}
	}
	
	private func availableUpdates() -> [App] {
		let includeExternal = AppListSettings.shared.includeAppsWithLimitedSupport
		return UpdateCheckCoordinator.shared.appProvider.updatableApps
			.filter { includeExternal || $0.usesBuiltInUpdater }
			.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
	}
	
	private func updateBadgeCount() {
		guard let button = statusItem?.button else { return }
		let count = availableUpdates().count
		if count > 0 {
			button.title = " \(NumberFormatter.localizedString(from: NSNumber(value: count), number: .none))"
		} else {
			button.title = ""
		}
	}
	
	
	// MARK: - NSMenuDelegate
	
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()
		
		let updates = availableUpdates()
		let count = updates.count
		
		// Status header
		let format = NSLocalizedString("NumberOfUpdatesAvailable", comment: "number of updates available")
		let headerTitle = String.localizedStringWithFormat(format, count)
		let headerItem = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
		headerItem.isEnabled = false
		menu.addItem(headerItem)
		
		let builtInUpdatable = updates.filter { $0.usesBuiltInUpdater && !$0.isUpdating }
		if !builtInUpdatable.isEmpty {
			let updateAllTitle = String(
				format: NSLocalizedString("MenuBarUpdateAllTitle", value: "Update All (%d)", comment: "Menu bar item to install all directly updatable apps."),
				builtInUpdatable.count
			)
			let updateAllItem = NSMenuItem(title: updateAllTitle, action: #selector(updateAllApps(_:)), keyEquivalent: "")
			updateAllItem.target = self
			menu.addItem(updateAllItem)
		}
		
		if !updates.isEmpty {
			menu.addItem(.separator())
			
			for app in updates {
				let versionInfo = app.localizedVersionInformation?.combined(includeNew: true) ?? ""
				let itemTitle = versionInfo.isEmpty ? app.name : "\(app.name) — \(versionInfo)"
				let item = NSMenuItem(title: itemTitle, action: #selector(handleAppMenuItem(_:)), keyEquivalent: "")
				item.target = self
				item.representedObject = app
				
				IconCache.shared.icon(for: app) { image in
					let iconCopy = (image.copy() as? NSImage) ?? image
					iconCopy.size = NSSize(width: 16, height: 16)
					item.image = iconCopy
				}
				
				menu.addItem(item)
			}
		}
		
		menu.addItem(.separator())
		
		let checkItem = NSMenuItem(
			title: NSLocalizedString("MenuBarCheckForUpdatesTitle", value: "Check for Updates…", comment: "Menu bar item to trigger an update check."),
			action: #selector(checkForUpdates(_:)),
			keyEquivalent: "r"
		)
		checkItem.target = self
		menu.addItem(checkItem)
		
		let openItem = NSMenuItem(
			title: NSLocalizedString("MenuBarOpenAppTitle", value: "Open Past Due", comment: "Menu bar item to bring the main Past Due window to the front."),
			action: #selector(openMainWindow(_:)),
			keyEquivalent: ""
		)
		openItem.target = self
		menu.addItem(openItem)
		
		menu.addItem(.separator())
		
		let quitItem = NSMenuItem(
			title: NSLocalizedString("MenuBarQuitTitle", value: "Quit Past Due", comment: "Menu bar item to quit Past Due."),
			action: #selector(quitApp(_:)),
			keyEquivalent: "q"
		)
		quitItem.target = self
		menu.addItem(quitItem)
	}
	
	
	// MARK: - Actions
	
	@objc private func updateAllApps(_ sender: NSMenuItem) {
		let builtInUpdatable = availableUpdates().filter { $0.usesBuiltInUpdater && !$0.isUpdating }
		if builtInUpdatable.contains(where: { $0.bundle.source == .appStore }) {
			try? AppStoreUpdateOperation.prepareForUpdates()
		}
		for app in builtInUpdatable {
			app.performUpdate(isBulkUpdate: builtInUpdatable.count > 1)
		}
	}
	
	@objc private func handleAppMenuItem(_ sender: NSMenuItem) {
		showMainWindowHandler?()
		if let app = sender.representedObject as? App,
		   app.usesBuiltInUpdater,
		   !app.isUpdating {
			app.performUpdate()
		}
	}
	
	@objc private func checkForUpdates(_ sender: NSMenuItem) {
		UpdateCheckCoordinator.shared.run()
	}
	
	@objc private func openMainWindow(_ sender: NSMenuItem) {
		showMainWindowHandler?()
	}
	
	@objc private func quitApp(_ sender: NSMenuItem) {
		NSApp.terminate(nil)
	}
	
}
