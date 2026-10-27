//
//  BackgroundUpdateScheduler.swift
//  Latest
//
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import UserNotifications

/// Schedules periodic update checks while Past Due is running and notifies the user about newly found updates.
final class BackgroundUpdateScheduler: NSObject, Observer {
	
	/// The shared scheduler.
	static let shared = BackgroundUpdateScheduler()
	
	let id = UUID()
	
	/// The identifier of the posted notification. Reusing it replaces earlier notifications instead of stacking them.
	private static let notificationIdentifier = "PastDue.UpdatesAvailable"
	
	/// The system scheduler running the periodic activity, if automatic checks are enabled.
	private var activityScheduler: NSBackgroundActivityScheduler?
	
	/// The interval the current activity scheduler was configured with.
	private var scheduledInterval: BackgroundCheckSettings.Interval?
	
	/// Completion handlers of scheduled activities waiting for the running check to finish.
	private var pendingActivityCompletions = [() -> Void]()
	
	/// Handler invoked when the user clicks a notification.
	var showMainWindowHandler: (() -> Void)?
	
	private override init() {
		super.init()
	}
	
	
	// MARK: - Lifecycle
	
	/// Starts observing settings and update check results. Call once at launch.
	func start() {
		UNUserNotificationCenter.current().delegate = self
		
		NotificationCenter.default.addObserver(self, selector: #selector(updateCheckDidFinish(_:)), name: UpdateCheckCoordinator.didFinishCheckingNotification, object: nil)
		
		BackgroundCheckSettings.shared.add(self) { [weak self] in
			self?.settingsDidChange()
		}
		
		settingsDidChange()
	}
	
	/// Reconfigures the activity scheduler to match the current settings.
	private func settingsDidChange() {
		let settings = BackgroundCheckSettings.shared
		
		guard settings.automaticChecksEnabled else {
			invalidateScheduler()
			return
		}
		
		if settings.notificationsEnabled {
			requestNotificationAuthorizationIfNeeded()
		}
		
		// Only recreate the scheduler if the interval changed
		guard activityScheduler == nil || scheduledInterval != settings.checkInterval else { return }
		invalidateScheduler()
		
		let interval = settings.checkInterval
		let scheduler = NSBackgroundActivityScheduler(identifier: "\(Bundle.main.bundleIdentifier ?? "PastDue").background-update-check")
		scheduler.repeats = true
		scheduler.interval = interval.timeInterval
		scheduler.tolerance = interval.timeInterval / 10
		scheduler.qualityOfService = .utility
		scheduler.schedule { [weak self] completion in
			guard let self else {
				completion(.finished)
				return
			}
			
			DispatchQueue.main.async {
				self.performScheduledCheck {
					completion(.finished)
				}
			}
		}
		
		activityScheduler = scheduler
		scheduledInterval = interval
	}
	
	private func invalidateScheduler() {
		activityScheduler?.invalidate()
		activityScheduler = nil
		scheduledInterval = nil
	}
	
	
	// MARK: - Checking
	
	/// Runs an update check and calls the completion once it finished.
	private func performScheduledCheck(completion: @escaping () -> Void) {
		dispatchPrecondition(condition: .onQueue(.main))
		
		pendingActivityCompletions.append(completion)
		
		// A check may already be running, e.g. triggered by the user. Wait for it instead of starting another one.
		if !UpdateCheckCoordinator.shared.isRunning {
			UpdateCheckCoordinator.shared.run()
		}
	}
	
	@objc private func updateCheckDidFinish(_ notification: Notification) {
		dispatchPrecondition(condition: .onQueue(.main))
		
		BackgroundCheckSettings.shared.lastCheckDate = Date()
		evaluateNotifications()
		
		let completions = pendingActivityCompletions
		pendingActivityCompletions.removeAll()
		completions.forEach { $0() }
	}
	
	
	// MARK: - Notifications
	
	/// Whether the user can currently see the list of updates.
	private var userIsLookingAtUpdates: Bool {
		NSApp.isActive && NSApp.windows.contains { $0.windowController is MainWindowController && $0.isVisible && !$0.isMiniaturized }
	}
	
	/// The updates currently available, matching what the update list shows.
	private var availableEntries: [UpdateNotificationPlanner.Entry] {
		let includeLimitedSupport = AppListSettings.shared.includeAppsWithLimitedSupport
		return UpdateCheckCoordinator.shared.appProvider
			.availableUpdates(where: { includeLimitedSupport || $0.usesBuiltInUpdater })
			.map { app in
				let version = app.remoteVersion.map { "\($0.versionNumber ?? "")-\($0.buildNumber ?? "")" } ?? ""
				return UpdateNotificationPlanner.Entry(bundleIdentifier: app.bundleIdentifier, name: app.name, version: version)
			}
	}
	
	/// Posts a notification for updates the user has not seen yet.
	private func evaluateNotifications() {
		var settings = BackgroundCheckSettings.shared
		let entries = availableEntries
		
		// Without notifications, simply keep the known set in sync so that enabling them later does not report old updates.
		let canNotify = settings.automaticChecksEnabled && settings.notificationsEnabled
		let plan = UpdateNotificationPlanner.plan(available: entries, known: settings.notifiedUpdateKeys, userIsLookingAtUpdates: userIsLookingAtUpdates || !canNotify)
		settings.notifiedUpdateKeys = plan.knownKeys
		
		guard !plan.newEntries.isEmpty else { return }
		postNotification(for: plan.newEntries)
	}
	
	private func postNotification(for entries: [UpdateNotificationPlanner.Entry]) {
		let center = UNUserNotificationCenter.current()
		center.getNotificationSettings { notificationSettings in
			guard notificationSettings.authorizationStatus == .authorized || notificationSettings.authorizationStatus == .provisional else { return }
			
			let content = UNMutableNotificationContent()
			content.title = UpdateNotificationPlanner.title(for: entries)
			content.body = UpdateNotificationPlanner.body(for: entries)
			content.sound = nil
			
			let request = UNNotificationRequest(identifier: Self.notificationIdentifier, content: content, trigger: nil)
			center.add(request)
		}
	}
	
	/// Asks for permission to post notifications, if not yet determined.
	func requestNotificationAuthorizationIfNeeded(completion: ((Bool) -> Void)? = nil) {
		let center = UNUserNotificationCenter.current()
		center.getNotificationSettings { notificationSettings in
			switch notificationSettings.authorizationStatus {
			case .notDetermined:
				center.requestAuthorization(options: [.alert, .badge]) { granted, _ in
					DispatchQueue.main.async { completion?(granted) }
				}
			case .authorized, .provisional:
				DispatchQueue.main.async { completion?(true) }
			default:
				DispatchQueue.main.async { completion?(false) }
			}
		}
	}
	
	/// Marks all currently available updates as known, e.g. right after the user enabled notifications.
	func markCurrentUpdatesAsKnown() {
		BackgroundCheckSettings.shared.notifiedUpdateKeys = Set(availableEntries.map(\.key))
	}
	
}

// MARK: - Notification Center Delegate

extension BackgroundUpdateScheduler: UNUserNotificationCenterDelegate {
	
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		DispatchQueue.main.async {
			self.showMainWindowHandler?()
			completionHandler()
		}
	}
	
	func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		// Show banners even while Past Due is frontmost but its window is closed
		completionHandler([.banner, .list])
	}
	
}
