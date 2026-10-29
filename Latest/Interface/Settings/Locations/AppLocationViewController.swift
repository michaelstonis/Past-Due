//
//  AppDirectoryViewController.swift
//  Latest
//
//  Created by Max Langer on 29.02.24.
//  Copyright © 2024 Max Langer. All rights reserved.
//

import AppKit

/// View displaying a list of directories to be checked for apps with updates.
class AppDirectoryViewController: SettingsTabItemViewController, NSTableViewDataSource, NSTableViewDelegate {
	
	// MARK: - View Lifecycle
	
	@IBOutlet private weak var tableView: NSTableView!
	@IBOutlet private weak var actionControl: NSSegmentedControl!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		validateButtons()
	}
	
	private lazy var directoryStore: AppDirectoryStore = {
		AppDirectoryStore(updateHandler: { [weak self] in
			self?.tableView.reloadData()
			self?.validateButtons()
		})
	}()
	
	
	// MARK: - Table
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		directoryStore.allURLs.count
	}

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("directoryCellView"), owner: self) as? AppDirectoryCellView else { return nil }
		let url = directoryStore.allURLs[row]
		view.configure(url: url, isEnabled: directoryStore.isEnabled(url)) { [weak self] enabled in
			self?.directoryStore.setEnabled(enabled, for: url)
		}
		
		return view
	}
	
	func tableViewSelectionDidChange(_ notification: Notification) {
		validateButtons()
	}
	
	
	// MARK: - Actions
	
	/// Possible actions on the segmented control.
	private enum Action: Int {
		/// Add a new directory to the list.
		case add = 0
		
		/// Remove the selected directory from the list.
		case delete = 1
	}
	
	@IBAction func performAction(_ sender: NSSegmentedControl) {
		switch Action(rawValue: sender.selectedSegment) {
		case .add:
			presentOpenPanel()
		case .delete:
			let selectedIndex = tableView.selectedRow
			guard selectedIndex != -1 else { return }
			let url = directoryStore.allURLs[selectedIndex]
			if directoryStore.canRemove(url) {
				directoryStore.remove(url)
			}
		case .none:
			()
		}
	}
	
	private func validateButtons() {
		let selectedIndex = tableView.selectedRow
		let enabled = if selectedIndex == -1 {
			false
		} else {
			directoryStore.canRemove(directoryStore.allURLs[selectedIndex])
		}
		
		actionControl.setEnabled(enabled, forSegment: Action.delete.rawValue)
	}
	
	private func presentOpenPanel() {
		guard let window = self.view.window else { return }
		let panel = NSOpenPanel()
		panel.canChooseFiles = false
		panel.canChooseDirectories = true
		
		panel.beginSheetModal(for: window) { [weak self] response in
			guard let self, response == .OK else { return }
			for url in panel.urls {
				if Self.isBroadScanRoot(url) {
					let alert = NSAlert()
					alert.alertStyle = .warning
					alert.messageText = NSLocalizedString("BroadScanDirectoryWarningTitle", value: "Broad Scan Location Selected", comment: "Warning title when a user selects a root or home directory as an app scan location.")
					alert.informativeText = String(
						format: NSLocalizedString("BroadScanDirectoryWarningMessage", value: "Scanning \"%@\" recursively may take a long time and trigger permission prompts. Consider choosing a more specific Applications folder instead.", comment: "Warning message when a user selects a broad scan directory."),
						url.path
					)
					alert.addButton(withTitle: NSLocalizedString("AddAnywayAction", value: "Add Anyway", comment: "Button to confirm adding a broad directory."))
					alert.addButton(withTitle: NSLocalizedString("CancelAction", value: "Cancel", comment: "Cancel button."))
					if alert.runModal() != .alertFirstButtonReturn {
						continue
					}
				}
				self.directoryStore.add(url)
			}
		}
	}
	
	static func isBroadScanRoot(_ url: URL) -> Bool {
		let standardized = url.standardizedFileURL.path
		let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
		return standardized == "/" || standardized == "/Users" || standardized == home || standardized.hasPrefix("/Volumes/") && standardized.split(separator: "/").count <= 2
	}
}
