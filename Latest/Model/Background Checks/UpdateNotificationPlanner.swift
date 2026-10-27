//
//  UpdateNotificationPlanner.swift
//  Latest
//
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Foundation

/// Pure logic deciding which available updates are new to the user and how a notification describing them reads.
enum UpdateNotificationPlanner {
	
	/// A lightweight description of an available update.
	struct Entry: Equatable {
		/// The bundle identifier of the app.
		let bundleIdentifier: String
		
		/// The display name of the app.
		let name: String
		
		/// A stable description of the remote version (version and build number).
		let version: String
		
		/// A key uniquely identifying this update for an app.
		var key: String {
			"\(bundleIdentifier)|\(version)"
		}
	}
	
	/// The result of planning a notification.
	struct Plan: Equatable {
		/// Entries the user has not yet been told about. Empty if no notification should be posted.
		let newEntries: [Entry]
		
		/// The set of keys to persist as already known after this plan has been applied.
		let knownKeys: Set<String>
	}
	
	/// Determines which updates are new.
	///
	/// - Parameters:
	///   - available: All updates currently available.
	///   - known: Keys of updates the user was already told about.
	///   - userIsLookingAtUpdates: Whether the user can currently see the update list. In that case nothing is notified, but all updates are marked as known.
	static func plan(available: [Entry], known: Set<String>, userIsLookingAtUpdates: Bool) -> Plan {
		let currentKeys = Set(available.map(\.key))
		
		// Updates that disappeared (installed or ignored) are pruned so that the stored set does not grow unbounded.
		if userIsLookingAtUpdates {
			return Plan(newEntries: [], knownKeys: currentKeys)
		}
		
		let newEntries = available
			.filter { !known.contains($0.key) }
			.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		return Plan(newEntries: newEntries, knownKeys: currentKeys)
	}
	
	/// The title of the notification for the given new updates.
	static func title(for entries: [Entry]) -> String {
		if entries.count == 1 {
			return NSLocalizedString("UpdateNotificationTitleSingle", value: "Update Available", comment: "Title of the user notification shown when a single new app update was found in the background.")
		}
		
		let format = NSLocalizedString("UpdateNotificationTitleMultiple", value: "%d Updates Available", comment: "Title of the user notification shown when multiple new app updates were found in the background. The placeholder is the number of updates.")
		return String.localizedStringWithFormat(format, entries.count)
	}
	
	/// The body text of the notification for the given new updates.
	static func body(for entries: [Entry]) -> String {
		switch entries.count {
		case 0:
			return ""
		case 1:
			let format = NSLocalizedString("UpdateNotificationBodySingle", value: "A new version of %@ is available.", comment: "Body of the user notification for a single new update. The placeholder is the app name.")
			return String.localizedStringWithFormat(format, entries[0].name)
		case 2, 3:
			let names = ListFormatter.localizedString(byJoining: entries.map(\.name))
			let format = NSLocalizedString("UpdateNotificationBodyList", value: "New versions of %@ are available.", comment: "Body of the user notification for two or three new updates. The placeholder is a localized list of app names.")
			return String.localizedStringWithFormat(format, names)
		default:
			let shown = entries.prefix(2).map(\.name)
			let format = NSLocalizedString("UpdateNotificationBodyMany", value: "New versions of %@, %@ and %d more apps are available.", comment: "Body of the user notification for four or more new updates. The placeholders are two app names and the number of remaining apps.")
			return String.localizedStringWithFormat(format, shown[0], shown[1], entries.count - 2)
		}
	}
	
}
