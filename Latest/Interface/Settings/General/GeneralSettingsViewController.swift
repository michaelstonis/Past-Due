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
	
	private var automaticChecksCheckbox: NSButton?
	private var intervalPopUpButton: NSPopUpButton?
	private var notificationsCheckbox: NSButton?
	private var launchAtLoginCheckbox: NSButton?
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
		
		let separator = NSBox()
		separator.boxType = .separator
		let separatorRow = gridView.addRow(with: [NSGridCell.emptyContentView, separator])
		separatorRow.topPadding = 10
		separatorRow.bottomPadding = 6
		separatorRow.mergeCells(in: NSRange(location: 0, length: 2))
		
		let sectionLabel = NSTextField(labelWithString: NSLocalizedString("BackgroundUpdatesSectionLabel", value: "Updates:", comment: "Label in General settings for background update check options."))
		sectionLabel.alignment = .right
		
		let autoCheckButton = NSButton(
			checkboxWithTitle: NSLocalizedString("CheckAutomaticallyTitle", value: "Check for updates in the background", comment: "Checkbox title to enable periodic background update checks."),
			target: self,
			action: #selector(toggleAutomaticChecks(_:))
		)
		self.automaticChecksCheckbox = autoCheckButton
		gridView.addRow(with: [sectionLabel, autoCheckButton])
		
		let frequencyLabel = NSTextField(labelWithString: NSLocalizedString("CheckFrequencyLabel", value: "Frequency:", comment: "Label for the background update check frequency pop-up button."))
		frequencyLabel.alignment = .right
		
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
		
		let notifyButton = NSButton(
			checkboxWithTitle: NSLocalizedString("NotifyWhenUpdatesAvailableTitle", value: "Notify when new updates are available", comment: "Checkbox title to post a macOS user notification when background checks find new updates."),
			target: self,
			action: #selector(toggleNotifications(_:))
		)
		self.notificationsCheckbox = notifyButton
		gridView.addRow(with: [NSGridCell.emptyContentView, notifyButton])
		
		let loginButton = NSButton(
			checkboxWithTitle: NSLocalizedString("LaunchAtLoginTitle", value: "Open Past Due at login", comment: "Checkbox title to register Past Due as a login item."),
			target: self,
			action: #selector(toggleLaunchAtLogin(_:))
		)
		self.launchAtLoginCheckbox = loginButton
		gridView.addRow(with: [NSGridCell.emptyContentView, loginButton])
		
		let cliSeparator = NSBox()
		cliSeparator.boxType = .separator
		let cliSeparatorRow = gridView.addRow(with: [NSGridCell.emptyContentView, cliSeparator])
		cliSeparatorRow.topPadding = 10
		cliSeparatorRow.bottomPadding = 6
		cliSeparatorRow.mergeCells(in: NSRange(location: 0, length: 2))
		
		let cliLabel = NSTextField(labelWithString: NSLocalizedString("CommandLineSectionLabel", value: "Command Line:", comment: "Label in General settings for installing the past-due CLI command."))
		cliLabel.alignment = .right
		
		let cliButton = NSButton(
			title: NSLocalizedString("InstallCLITitle", value: "Install 'past-due' Command…", comment: "Button title to install /usr/local/bin/past-due symlink."),
			target: self,
			action: #selector(installCLICommand(_:))
		)
		cliButton.bezelStyle = .rounded
		self.installCLIButton = cliButton
		gridView.addRow(with: [cliLabel, cliButton])
		
		refreshBackgroundUpdateControls()
		
		view.layoutSubtreeIfNeeded()
		view.setFrameSize(view.fittingSize)
	}
	
	private func refreshBackgroundUpdateControls() {
		let settings = BackgroundCheckSettings.shared
		let enabled = settings.automaticChecksEnabled
		
		automaticChecksCheckbox?.state = enabled ? .on : .off
		intervalPopUpButton?.selectItem(withTag: settings.checkInterval.rawValue)
		intervalPopUpButton?.isEnabled = enabled
		notificationsCheckbox?.state = settings.notificationsEnabled ? .on : .off
		notificationsCheckbox?.isEnabled = enabled
		launchAtLoginCheckbox?.state = settings.launchAtLogin ? .on : .off
		
		if CommandLineInstaller.isInstalled {
			installCLIButton?.title = NSLocalizedString("CLIInstalledTitle", value: "Installed at /usr/local/bin/past-due", comment: "Button title shown when /usr/local/bin/past-due is already installed.")
			installCLIButton?.isEnabled = false
		} else {
			installCLIButton?.title = NSLocalizedString("InstallCLITitle", value: "Install 'past-due' Command…", comment: "Button title to install /usr/local/bin/past-due symlink.")
			installCLIButton?.isEnabled = true
		}
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
