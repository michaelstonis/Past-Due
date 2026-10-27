//
//  BackgroundUpdateCheckTest.swift
//  Latest Tests
//

import XCTest
@testable import Latest

final class BackgroundUpdateCheckTest: XCTestCase {

	func testAppListSettingsEnablesLimitedSupportAppsByDefault() {
		// Ensure that on a fresh install (where IncludeAppsWithLimitedSupportKey is unset in UserDefaults),
		// apps detected via the Homebrew Cask catalog with external updaters are shown by default.
		let previousObject = UserDefaults.standard.object(forKey: "IncludeAppsWithLimitedSupportKey")
		defer {
			if let previousObject {
				UserDefaults.standard.set(previousObject, forKey: "IncludeAppsWithLimitedSupportKey")
			} else {
				UserDefaults.standard.removeObject(forKey: "IncludeAppsWithLimitedSupportKey")
			}
		}

		UserDefaults.standard.removeObject(forKey: "IncludeAppsWithLimitedSupportKey")
		XCTAssertTrue(AppListSettings.shared.includeAppsWithLimitedSupport)
	}

	func testBackgroundCheckSettingsDefaultsAndPersistence() throws {
		let suiteName = "BackgroundCheckSettingsTest.\(UUID().uuidString)"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
		addTeardownBlock {
			defaults.removePersistentDomain(forName: suiteName)
		}

		var settings = BackgroundCheckSettings(defaults: defaults)
		XCTAssertFalse(settings.automaticChecksEnabled)
		XCTAssertEqual(settings.checkInterval, .daily)
		XCTAssertTrue(settings.notificationsEnabled)
		XCTAssertFalse(settings.showMenuBarExtra)
		XCTAssertNil(settings.lastCheckDate)
		XCTAssertTrue(settings.notifiedUpdateKeys.isEmpty)

		settings.automaticChecksEnabled = true
		settings.checkInterval = .sixHours
		settings.notificationsEnabled = false
		settings.showMenuBarExtra = true
		settings.notifiedUpdateKeys = ["com.example.one|1.0-100", "com.example.two|2.0-200"]

		let reloaded = BackgroundCheckSettings(defaults: defaults)
		XCTAssertTrue(reloaded.automaticChecksEnabled)
		XCTAssertEqual(reloaded.checkInterval, .sixHours)
		XCTAssertFalse(reloaded.notificationsEnabled)
		XCTAssertTrue(reloaded.showMenuBarExtra)
		XCTAssertEqual(reloaded.notifiedUpdateKeys, ["com.example.one|1.0-100", "com.example.two|2.0-200"])
	}

	func testAppDirectoryStoreAllowsTogglingDefaultAndCustomDirectories() throws {
		let suiteName = "AppDirectoryStoreTest.\(UUID().uuidString)"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
		addTeardownBlock {
			defaults.removePersistentDomain(forName: suiteName)
		}

		var callbackCount = 0
		let store = AppDirectoryStore(defaults: defaults) {
			callbackCount += 1
		}

		guard let firstDefault = AppDirectoryStore.defaultURLs.first else {
			return
		}

		// Default directories are enabled by default and cannot be deleted, but CAN be toggled off
		XCTAssertTrue(store.isEnabled(firstDefault))
		XCTAssertFalse(store.canRemove(firstDefault))
		XCTAssertTrue(store.URLs.contains(firstDefault))

		store.setEnabled(false, for: firstDefault)
		XCTAssertFalse(store.isEnabled(firstDefault))
		XCTAssertTrue(store.allURLs.contains(firstDefault))
		XCTAssertFalse(store.URLs.contains(firstDefault))
		XCTAssertGreaterThan(callbackCount, 0)

		// Re-enabling restores it to active URLs
		store.setEnabled(true, for: firstDefault)
		XCTAssertTrue(store.isEnabled(firstDefault))
		XCTAssertTrue(store.URLs.contains(firstDefault))
	}

	func testNotificationPlannerReportsOnlyUnseenUpdatesAndPrunesResolvedOnes() {
		let discord = UpdateNotificationPlanner.Entry(bundleIdentifier: "com.hnc.Discord", name: "Discord", version: "0.0.420-0.0.420")
		let figma = UpdateNotificationPlanner.Entry(bundleIdentifier: "com.figma.Desktop", name: "Figma", version: "126.10.13-126.10.13")
		let cursor = UpdateNotificationPlanner.Entry(bundleIdentifier: "com.todesktop.230313mzl4w4u92", name: "Cursor", version: "3.27.22-3.27.22")

		// discord was already notified; an older resolved app was also in known
		let known: Set<String> = [discord.key, "com.old.resolved|1.0-1"]

		let plan = UpdateNotificationPlanner.plan(
			available: [figma, discord, cursor],
			known: known,
			userIsLookingAtUpdates: false
		)

		// New entries should be sorted alphabetically and exclude already-known Discord
		XCTAssertEqual(plan.newEntries, [cursor, figma])
		// Known keys should contain all currently available updates and prune com.old.resolved
		XCTAssertEqual(plan.knownKeys, [discord.key, figma.key, cursor.key])
	}

	func testNotificationPlannerSuppressesNotificationWhenUserIsLookingAtUpdates() {
		let figma = UpdateNotificationPlanner.Entry(bundleIdentifier: "com.figma.Desktop", name: "Figma", version: "126.10.13-126.10.13")
		let plan = UpdateNotificationPlanner.plan(
			available: [figma],
			known: [],
			userIsLookingAtUpdates: true
		)

		XCTAssertTrue(plan.newEntries.isEmpty)
		XCTAssertEqual(plan.knownKeys, [figma.key])
	}

	func testNotificationPlannerFormatsTitlesAndBodies() {
		let a = UpdateNotificationPlanner.Entry(bundleIdentifier: "a", name: "Alpha", version: "1.0")
		let b = UpdateNotificationPlanner.Entry(bundleIdentifier: "b", name: "Bravo", version: "1.0")
		let c = UpdateNotificationPlanner.Entry(bundleIdentifier: "c", name: "Charlie", version: "1.0")
		let d = UpdateNotificationPlanner.Entry(bundleIdentifier: "d", name: "Delta", version: "1.0")

		XCTAssertEqual(UpdateNotificationPlanner.title(for: [a]), "Update Available")
		XCTAssertTrue(UpdateNotificationPlanner.body(for: [a]).contains("Alpha"))

		XCTAssertEqual(UpdateNotificationPlanner.title(for: [a, b]), "2 Updates Available")
		XCTAssertTrue(UpdateNotificationPlanner.body(for: [a, b]).contains("Alpha"))
		XCTAssertTrue(UpdateNotificationPlanner.body(for: [a, b]).contains("Bravo"))

		XCTAssertEqual(UpdateNotificationPlanner.title(for: [a, b, c, d]), "4 Updates Available")
		XCTAssertTrue(UpdateNotificationPlanner.body(for: [a, b, c, d]).contains("2 more"))
	}

}
