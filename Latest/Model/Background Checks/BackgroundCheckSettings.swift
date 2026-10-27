//
//  BackgroundCheckSettings.swift
//  Latest
//
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Foundation
import ServiceManagement

private let AutomaticChecksEnabledKey = "AutomaticUpdateChecksEnabledKey"
private let CheckIntervalKey = "AutomaticUpdateCheckIntervalKey"
private let NotificationsEnabledKey = "UpdateNotificationsEnabledKey"
private let LastCheckDateKey = "LastUpdateCheckDateKey"
private let NotifiedUpdateKeysKey = "NotifiedUpdateKeysKey"

/// Front end to the preferences controlling scheduled background update checks and notifications.
struct BackgroundCheckSettings: Observable {
	
	/// How often scheduled update checks run.
	enum Interval: Int, CaseIterable {
		case sixHours = 0
		case daily = 1
		case weekly = 2
		
		/// The interval duration in seconds.
		var timeInterval: TimeInterval {
			switch self {
			case .sixHours: return 6 * 60 * 60
			case .daily: return 24 * 60 * 60
			case .weekly: return 7 * 24 * 60 * 60
			}
		}
		
		/// A user-displayable name of the interval.
		var displayName: String {
			switch self {
			case .sixHours:
				return NSLocalizedString("CheckIntervalSixHours", value: "Every 6 Hours", comment: "Automatic update check interval option: every six hours.")
			case .daily:
				return NSLocalizedString("CheckIntervalDaily", value: "Daily", comment: "Automatic update check interval option: once per day.")
			case .weekly:
				return NSLocalizedString("CheckIntervalWeekly", value: "Weekly", comment: "Automatic update check interval option: once per week.")
			}
		}
	}
	
	var observers = [UUID : ObservationHandler]()
	
	private let defaults: UserDefaults
	
	init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
		defaults.register(defaults: [
			AutomaticChecksEnabledKey: false,
			CheckIntervalKey: Interval.daily.rawValue,
			NotificationsEnabledKey: true
		])
	}
	
	static var shared = BackgroundCheckSettings()
	
	
	// MARK: - Preferences
	
	/// Whether Past Due periodically checks for updates while running, including when its window is closed.
	var automaticChecksEnabled: Bool {
		get { defaults.bool(forKey: AutomaticChecksEnabledKey) }
		set { set(newValue, forKey: AutomaticChecksEnabledKey) }
	}
	
	/// How often automatic checks run.
	var checkInterval: Interval {
		get { Interval(rawValue: defaults.integer(forKey: CheckIntervalKey)) ?? .daily }
		set { set(newValue.rawValue, forKey: CheckIntervalKey) }
	}
	
	/// Whether a user notification is posted when automatic checks find new updates.
	var notificationsEnabled: Bool {
		get { defaults.bool(forKey: NotificationsEnabledKey) }
		set { set(newValue, forKey: NotificationsEnabledKey) }
	}
	
	/// The date of the last completed update check.
	var lastCheckDate: Date? {
		get { defaults.object(forKey: LastCheckDateKey) as? Date }
		set { defaults.set(newValue, forKey: LastCheckDateKey) }
	}
	
	/// Keys of updates the user has already been told about (either via notification or by seeing them in the window).
	var notifiedUpdateKeys: Set<String> {
		get { Set(defaults.stringArray(forKey: NotifiedUpdateKeysKey) ?? []) }
		set { defaults.set(newValue.sorted(), forKey: NotifiedUpdateKeysKey) }
	}
	
	
	// MARK: - Launch at Login
	
	/// Whether Past Due is registered to open at login.
	var launchAtLogin: Bool {
		let status = SMAppService.mainApp.status
		return status == .enabled || status == .requiresApproval
	}
	
	/// Registers or unregisters Past Due as a login item.
	func setLaunchAtLogin(_ enabled: Bool) throws {
		if enabled {
			try SMAppService.mainApp.register()
			if SMAppService.mainApp.status == .requiresApproval {
				SMAppService.openSystemSettingsLoginItems()
			}
		} else {
			try SMAppService.mainApp.unregister()
		}
	}
	
	
	// MARK: - Utilities
	
	private func set(_ value: Any, forKey key: String) {
		defaults.set(value, forKey: key)
		
		DispatchQueue.main.async {
			self.notify()
		}
	}
	
}
