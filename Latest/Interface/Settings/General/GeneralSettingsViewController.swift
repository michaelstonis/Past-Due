//
//  GeneralSettingsViewController.swift
//  Latest
//
//  Created by Max Langer on 27.12.24.
//  Copyright © 2024 Max Langer. All rights reserved.
//

import AppKit

/// Controller for settings of the General tab.
class GeneralSettingsViewController: SettingsTabItemViewController {
	
	private var includeHomebrewCheckbox: NSButton?
	private var includeNPMCheckbox: NSButton?
	private var includeUVCheckbox: NSButton?
	private var includeCargoCheckbox: NSButton?
	private var includeMacPortsCheckbox: NSButton?
	private var includeNixCheckbox: NSButton?
	private var automaticChecksCheckbox: NSButton?
	private var intervalPopUpButton: NSPopUpButton?
	private var notificationsCheckbox: NSButton?
	private var launchAtLoginCheckbox: NSButton?
	private var showMenuBarCheckbox: NSButton?
	private var installCLIButton: NSButton?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		setupBackgroundUpdateControls()
		updateInstallHelperBannerVisibility()
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		refreshBackgroundUpdateControls()
	}
	
	// MARK: - Check Includes
	
	/// Whether apps with limited support should be included in the app list.
	@objc var includeAppsWithLimitedSupport: Bool {
		get {
			AppListSettings.shared.includeAppsWithLimitedSupport
		}
		set {
			AppListSettings.shared.includeAppsWithLimitedSupport = newValue
		}
	}
	
	/// Whether apps with no support should be included in the app list.
	@objc var includeUnsupportedApps: Bool {
		get {
			AppListSettings.shared.includeUnsupportedApps
		}
		set {
			AppListSettings.shared.includeUnsupportedApps = newValue
		}
	}
	
	
	// MARK: - Background Updates
	
	private func setupBackgroundUpdateControls() {
		guard let gridView = view.subviews.compactMap({ $0 as? NSGridView }).first else {
			return
		}
		
		// Allow the first column to expand dynamically to fit wider labels ("Frequency:", "Command Line:")
		// instead of being pinned to the "Include:" label's hugging priority (1000 in Main.storyboard).
		if gridView.numberOfColumns > 0 {
			for rowIndex in 0..<gridView.numberOfRows {
				if let cellView = gridView.cell(atColumnIndex: 0, rowIndex: rowIndex).contentView {
					cellView.setContentHuggingPriority(.defaultLow, for: .horizontal)
					cellView.setContentCompressionResistancePriority(.required, for: .horizontal)
				}
			}
		}
		
		func makeSectionLabel(_ title: String) -> NSTextField {
			let label = NSTextField(labelWithString: title)
			label.alignment = .right
			label.setContentHuggingPriority(.defaultLow, for: .horizontal)
			label.setContentCompressionResistancePriority(.required, for: .horizontal)
			return label
		}
		
		let pkgSeparator = NSBox()
		pkgSeparator.boxType = .separator
		let pkgSeparatorRow = gridView.addRow(with: [NSGridCell.emptyContentView, pkgSeparator])
		pkgSeparatorRow.topPadding = 10
		pkgSeparatorRow.bottomPadding = 6
		pkgSeparatorRow.mergeCells(in: NSRange(location: 0, length: 2))
		
		let packagesLabel = makeSectionLabel(NSLocalizedString("PackagesSectionLabel", value: "Packages:", comment: "Label in General settings for package manager toggles."))
		
		let homebrewButton = NSButton(
			checkboxWithTitle: NSLocalizedString("IncludeHomebrewUpdatesTitle", value: "Homebrew (Casks & CLI Formulae)", comment: "Checkbox title to include Homebrew-managed apps and formulae in the sidebar."),
			target: self,
			action: #selector(toggleIncludeHomebrewUpdates(_:))
		)
		self.includeHomebrewCheckbox = homebrewButton
		let homebrewRow = gridView.addRow(with: [packagesLabel, homebrewButton])
		homebrewRow.cell(at: 1).xPlacement = .leading
		
		let npmButton = NSButton(
			checkboxWithTitle: NSLocalizedString("IncludeNPMUpdatesTitle", value: "Node.js Global CLI (npm -g)", comment: "Checkbox title to include global npm packages in the sidebar."),
			target: self,
			action: #selector(toggleIncludeNPMUpdates(_:))
		)
		self.includeNPMCheckbox = npmButton
		let npmRow = gridView.addRow(with: [NSGridCell.emptyContentView, npmButton])
		npmRow.topPadding = 2
		npmRow.cell(at: 1).xPlacement = .leading
		
		let uvButton = NSButton(
			checkboxWithTitle: NSLocalizedString("IncludeUVUpdatesTitle", value: "Python CLI Tools (uv / pipx)", comment: "Checkbox title to include uv and pipx Python CLI tools in the sidebar."),
			target: self,
			action: #selector(toggleIncludeUVUpdates(_:))
		)
		self.includeUVCheckbox = uvButton
		let uvRow = gridView.addRow(with: [NSGridCell.emptyContentView, uvButton])
		uvRow.topPadding = 2
		uvRow.cell(at: 1).xPlacement = .leading
		
		let cargoButton = NSButton(
			checkboxWithTitle: NSLocalizedString("IncludeCargoUpdatesTitle", value: "Rust CLI Crates (Cargo)", comment: "Checkbox title to include Cargo crates in the sidebar."),
			target: self,
			action: #selector(toggleIncludeCargoUpdates(_:))
		)
		self.includeCargoCheckbox = cargoButton
		let cargoRow = gridView.addRow(with: [NSGridCell.emptyContentView, cargoButton])
		cargoRow.topPadding = 2
		cargoRow.cell(at: 1).xPlacement = .leading
		
		let macportsButton = NSButton(
			checkboxWithTitle: NSLocalizedString("IncludeMacPortsUpdatesTitle", value: "MacPorts (port)", comment: "Checkbox title to include MacPorts packages in the sidebar."),
			target: self,
			action: #selector(toggleIncludeMacPortsUpdates(_:))
		)
		self.includeMacPortsCheckbox = macportsButton
		let macportsRow = gridView.addRow(with: [NSGridCell.emptyContentView, macportsButton])
		macportsRow.topPadding = 2
		macportsRow.cell(at: 1).xPlacement = .leading
		
		let nixButton = NSButton(
			checkboxWithTitle: NSLocalizedString("IncludeNixUpdatesTitle", value: "Nix Packages (nix profile)", comment: "Checkbox title to include Nix profile packages in the sidebar."),
			target: self,
			action: #selector(toggleIncludeNixUpdates(_:))
		)
		self.includeNixCheckbox = nixButton
		let nixRow = gridView.addRow(with: [NSGridCell.emptyContentView, nixButton])
		nixRow.topPadding = 2
		nixRow.cell(at: 1).xPlacement = .leading
		
		let separator = NSBox()
		separator.boxType = .separator
		let separatorRow = gridView.addRow(with: [NSGridCell.emptyContentView, separator])
		separatorRow.topPadding = 10
		separatorRow.bottomPadding = 6
		separatorRow.mergeCells(in: NSRange(location: 0, length: 2))
		
		let sectionLabel = makeSectionLabel(NSLocalizedString("BackgroundUpdatesSectionLabel", value: "Updates:", comment: "Label in General settings for background update check options."))
		
		let autoCheckButton = NSButton(
			checkboxWithTitle: NSLocalizedString("CheckAutomaticallyTitle", value: "Check for updates in the background", comment: "Checkbox title to enable periodic background update checks."),
			target: self,
			action: #selector(toggleAutomaticChecks(_:))
		)
		self.automaticChecksCheckbox = autoCheckButton
		let autoCheckRow = gridView.addRow(with: [sectionLabel, autoCheckButton])
		autoCheckRow.cell(at: 1).xPlacement = .leading
		
		let frequencyLabel = makeSectionLabel(NSLocalizedString("CheckFrequencyLabel", value: "Frequency:", comment: "Label for the background update check frequency pop-up button."))
		
		let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
		for interval in BackgroundCheckSettings.Interval.allCases {
			popUp.addItem(withTitle: interval.displayName)
			popUp.lastItem?.tag = interval.rawValue
		}
		popUp.target = self
		popUp.action = #selector(changeCheckInterval(_:))
		self.intervalPopUpButton = popUp
		let frequencyRow = gridView.addRow(with: [frequencyLabel, popUp])
		frequencyRow.topPadding = 4
		frequencyRow.bottomPadding = 2
		frequencyRow.cell(at: 1).xPlacement = .leading
		
		let notifyButton = NSButton(
			checkboxWithTitle: NSLocalizedString("NotifyWhenUpdatesAvailableTitle", value: "Notify when new updates are available", comment: "Checkbox title to post a macOS user notification when background checks find new updates."),
			target: self,
			action: #selector(toggleNotifications(_:))
		)
		self.notificationsCheckbox = notifyButton
		let notifyRow = gridView.addRow(with: [NSGridCell.emptyContentView, notifyButton])
		notifyRow.cell(at: 1).xPlacement = .leading
		
		let loginButton = NSButton(
			checkboxWithTitle: NSLocalizedString("LaunchAtLoginTitle", value: "Open Past Due at login", comment: "Checkbox title to register Past Due as a login item."),
			target: self,
			action: #selector(toggleLaunchAtLogin(_:))
		)
		self.launchAtLoginCheckbox = loginButton
		let loginRow = gridView.addRow(with: [NSGridCell.emptyContentView, loginButton])
		loginRow.cell(at: 1).xPlacement = .leading
		
		let menuBarButton = NSButton(
			checkboxWithTitle: NSLocalizedString("ShowMenuBarExtraTitle", value: "Show Past Due in the menu bar", comment: "Checkbox title to show an NSStatusItem in the macOS menu bar with the available update count."),
			target: self,
			action: #selector(toggleShowMenuBarExtra(_:))
		)
		self.showMenuBarCheckbox = menuBarButton
		let menuBarRow = gridView.addRow(with: [NSGridCell.emptyContentView, menuBarButton])
		menuBarRow.cell(at: 1).xPlacement = .leading
		
		let cliSeparator = NSBox()
		cliSeparator.boxType = .separator
		let cliSeparatorRow = gridView.addRow(with: [NSGridCell.emptyContentView, cliSeparator])
		cliSeparatorRow.topPadding = 10
		cliSeparatorRow.bottomPadding = 6
		cliSeparatorRow.mergeCells(in: NSRange(location: 0, length: 2))
		
		let cliLabel = makeSectionLabel(NSLocalizedString("CommandLineSectionLabel", value: "Command Line:", comment: "Label in General settings for installing the past-due CLI command."))
		
		let cliButton = NSButton(
			title: NSLocalizedString("InstallCLITitle", value: "Install 'past-due' Command…", comment: "Button title to install /usr/local/bin/past-due symlink."),
			target: self,
			action: #selector(installCLICommand(_:))
		)
		cliButton.bezelStyle = .rounded
		self.installCLIButton = cliButton
		let cliRow = gridView.addRow(with: [cliLabel, cliButton])
		cliRow.cell(at: 1).xPlacement = .leading
		
		refreshBackgroundUpdateControls()
		
		view.layoutSubtreeIfNeeded()
		view.setFrameSize(view.fittingSize)
	}
	
	private func refreshBackgroundUpdateControls() {
		includeHomebrewCheckbox?.state = AppListSettings.shared.includeHomebrewUpdates ? .on : .off
		includeNPMCheckbox?.state = AppListSettings.shared.includeNPMUpdates ? .on : .off
		includeUVCheckbox?.state = AppListSettings.shared.includeUVUpdates ? .on : .off
		includeCargoCheckbox?.state = AppListSettings.shared.includeCargoUpdates ? .on : .off
		includeMacPortsCheckbox?.state = AppListSettings.shared.includeMacPortsUpdates ? .on : .off
		includeNixCheckbox?.state = AppListSettings.shared.includeNixUpdates ? .on : .off
		
		let settings = BackgroundCheckSettings.shared
		let enabled = settings.automaticChecksEnabled
		
		automaticChecksCheckbox?.state = enabled ? .on : .off
		intervalPopUpButton?.selectItem(withTag: settings.checkInterval.rawValue)
		intervalPopUpButton?.isEnabled = enabled
		notificationsCheckbox?.state = settings.notificationsEnabled ? .on : .off
		notificationsCheckbox?.isEnabled = enabled
		launchAtLoginCheckbox?.state = settings.launchAtLogin ? .on : .off
		showMenuBarCheckbox?.state = settings.showMenuBarExtra ? .on : .off
		
		if CommandLineInstaller.isInstalled {
			installCLIButton?.title = NSLocalizedString("CLIInstalledTitle", value: "Installed at /usr/local/bin/past-due", comment: "Button title shown when /usr/local/bin/past-due is already installed.")
			installCLIButton?.isEnabled = false
		} else {
			installCLIButton?.title = NSLocalizedString("InstallCLITitle", value: "Install 'past-due' Command…", comment: "Button title to install /usr/local/bin/past-due symlink.")
			installCLIButton?.isEnabled = true
		}
	}
	
	@objc private func toggleIncludeHomebrewUpdates(_ sender: NSButton) {
		AppListSettings.shared.includeHomebrewUpdates = (sender.state == .on)
	}
	
	@objc private func toggleIncludeNPMUpdates(_ sender: NSButton) {
		AppListSettings.shared.includeNPMUpdates = (sender.state == .on)
		UpdateCheckCoordinator.shared.refreshAfterHomebrewUpgrade()
	}
	
	@objc private func toggleIncludeUVUpdates(_ sender: NSButton) {
		AppListSettings.shared.includeUVUpdates = (sender.state == .on)
		UpdateCheckCoordinator.shared.refreshAfterHomebrewUpgrade()
	}
	
	@objc private func toggleIncludeCargoUpdates(_ sender: NSButton) {
		AppListSettings.shared.includeCargoUpdates = (sender.state == .on)
		UpdateCheckCoordinator.shared.refreshAfterHomebrewUpgrade()
	}
	
	@objc private func toggleIncludeMacPortsUpdates(_ sender: NSButton) {
		AppListSettings.shared.includeMacPortsUpdates = (sender.state == .on)
		UpdateCheckCoordinator.shared.refreshAfterHomebrewUpgrade()
	}
	
	@objc private func toggleIncludeNixUpdates(_ sender: NSButton) {
		AppListSettings.shared.includeNixUpdates = (sender.state == .on)
		UpdateCheckCoordinator.shared.refreshAfterHomebrewUpgrade()
	}
	
	@objc private func toggleAutomaticChecks(_ sender: NSButton) {
		let enabled = (sender.state == .on)
		BackgroundCheckSettings.shared.automaticChecksEnabled = enabled
		if enabled && BackgroundCheckSettings.shared.notificationsEnabled {
			BackgroundUpdateScheduler.shared.markCurrentUpdatesAsKnown()
			BackgroundUpdateScheduler.shared.requestNotificationAuthorizationIfNeeded()
		}
		refreshBackgroundUpdateControls()
	}
	
	@objc private func changeCheckInterval(_ sender: NSPopUpButton) {
		guard let tag = sender.selectedItem?.tag,
			  let interval = BackgroundCheckSettings.Interval(rawValue: tag) else {
			return
		}
		BackgroundCheckSettings.shared.checkInterval = interval
	}
	
	@objc private func toggleNotifications(_ sender: NSButton) {
		let enabled = (sender.state == .on)
		BackgroundCheckSettings.shared.notificationsEnabled = enabled
		if enabled {
			BackgroundUpdateScheduler.shared.markCurrentUpdatesAsKnown()
			BackgroundUpdateScheduler.shared.requestNotificationAuthorizationIfNeeded()
		}
	}
	
	@objc private func toggleLaunchAtLogin(_ sender: NSButton) {
		let enabled = (sender.state == .on)
		do {
			try BackgroundCheckSettings.shared.setLaunchAtLogin(enabled)
		} catch {
			NSAlert(error: error).runModal()
		}
		refreshBackgroundUpdateControls()
	}
	
	@objc private func toggleShowMenuBarExtra(_ sender: NSButton) {
		BackgroundCheckSettings.shared.showMenuBarExtra = (sender.state == .on)
	}
	
	@objc private func installCLICommand(_ sender: NSButton) {
		do {
			try CommandLineInstaller.install()
		} catch {
			NSAlert(error: error).runModal()
		}
		refreshBackgroundUpdateControls()
	}
	
	
	// MARK: - Install Helper
	
	@IBOutlet weak var installHelperOptInView: NSView!

	private func updateInstallHelperBannerVisibility() {
		do {
			try InstallHelper.verifyAvailability()
			installHelperOptInView.isHidden = true
		} catch {
			installHelperOptInView.isHidden = false
		}
	}
	
	@IBAction func registerInstallHelper(_ sender: Any) {
		AppStoreUpdateSettings.alwaysPerformManualUpdates.active = false
		try? InstallHelper.installHelper()
		
		updateInstallHelperBannerVisibility()
	}

}
