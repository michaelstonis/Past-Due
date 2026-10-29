//
//  AppCollection.swift
//  Latest
//
//  Created by Max Langer on 15.08.18.
//  Copyright © 2018 Max Langer. All rights reserved.
//

import Foundation

/// An interface for objects providing apps.
protocol AppProviding {
	
	/// Returns all apps currently in the data store.
	var allApps: [App] { get }

	/// Returns a list of apps with available updates that can be updated from within Latest.
	var updatableApps: [App] { get }

	/// Returns the apps with updates available matching the given condition.
	func availableUpdates(where condition: (App) -> Bool) -> [App]

	/// Returns the number of apps with updates available.
	func countOfAvailableUpdates(where condition: (App) -> Bool) -> Int
	
	/// The handler for notifying observers about changes to the update state.
	typealias ObserverHandler = (_ newValue: [App]) -> Void

	/// Adds the observer if it is not already registered.
	func addObserver(_ observer: NSObject, handler: @escaping ObserverHandler)
	
	/// Removes the observer.
	func removeObserver(_ observer: NSObject)
	
	/// Sets the ignored state for the given app.
	func setIgnoredState(_ ignored: Bool, for app: App)
	
	/// Skips the current update version for the given app until a newer version is released, or clears the skipped version if `nil`.
	func setSkippedVersion(_ version: Version?, for app: App)
	
}

/// The collection handling app bundles alongside there update representations.
class AppDataStore: AppProviding {
	
	/// The queue on which updates to the collection are being performed.
	private var updateQueue = DispatchQueue(label: "DataStoreQueue")
	
	/// Whether this store persists and restores discovered app bundles across launches.
	private let persistsCache: Bool
	
	private struct CachedBundleRecord: Codable {
		let versionNumber: String?
		let buildNumber: String?
		let name: String
		let bundleIdentifier: String
		let filePath: String
		let source: String
	}
	
	private static var cacheFileURL: URL? {
		FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
			.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.halfbuttonpress.PastDue")
			.appendingPathComponent("CachedAppBundles.json")
	}
	
	init(restoreFromCache: Bool = false) {
		self.persistsCache = restoreFromCache
		self.updateScheduler = DispatchSource.makeUserDataAddSource(queue: .global())
		self.setupScheduler()
		if restoreFromCache {
			self.restoreCachedBundles()
		}
	}

	
	// MARK: - Delegate Scheduling

	/// Schedules an update notification.
	private let updateScheduler: DispatchSourceUserDataAdd
	
	/// Sets up the scheduler.
	private func setupScheduler() {
		// Delay notifying observers to only let that notification occur in a certain interval
		// The handler runs on a background queue and sleeps, so it can fire after the store has been released. It must not assume `self` is still alive.
		updateScheduler.setEventHandler() { [weak self] in
			guard let self else { return }
			
			updateQueue.sync {
				let apps = Array(self.apps)
				self.notifyObservers(apps)
			}
		
			// Delay the next call for 0.6 seconds
			Thread.sleep(forTimeInterval: 0.6)
		}
		
		updateScheduler.activate()
	}
	
	/// Schedules an filter update and notifies observers of the updated app list
	private func scheduleFilterUpdate() {
		self.updateScheduler.add(data: 1)
	}
	
	
	// MARK: - App Providing
	
	/// The collection holding all apps that have been found.
	private(set) var apps = Set<App>() {
		didSet {
			// Schedule an update for observers
			self.scheduleFilterUpdate()
		}
	}
	
	/// Returns all apps currently in the data store.
	var allApps: [App] {
		updateQueue.sync {
			return Array(self.apps)
		}
	}

	/// A subset of apps that can be updated. Ignored apps are not part of this list.
	var updatableApps: [App] {
		updateQueue.sync {
			return self.apps.filter({ $0.updateAvailable && $0.usesBuiltInUpdater && !$0.isIgnored })
		}
	}
		
	/// Returns the apps with updates available matching the given condition.
	func availableUpdates(where condition: (App) -> Bool) -> [App] {
		updateQueue.sync {
			return self.apps.filter({ $0.updateAvailable && !$0.isIgnored && condition($0) })
		}
	}

	/// The cached count of apps with updates available
	func countOfAvailableUpdates(where condition: (App) -> Bool) -> Int {
		return availableUpdates(where: condition).count
	}
	
	/// Updates the store with the given set of app bundles.
	///
	/// It returns a set with matching app objects, containing the given bundles with their associated updates.
	func set(appBundles: Set<App.Bundle>) -> Set<App> {
		self.updateQueue.sync {
			let oldApps = self.apps
			self.apps = Set(appBundles.map({ bundle in
				if let app = oldApps.first(where: { $0.identifier == bundle.identifier }) {
					return app.with(bundle: bundle)
				}
				
				return App(
					bundle: bundle,
					update: nil,
					isIgnored: self.isIdentifierIgnored(bundle.bundleIdentifier),
					skippedVersion: self.skippedVersion(for: bundle.bundleIdentifier)
				)
			}))
			
			if self.persistsCache, !appBundles.isEmpty {
				self.saveCachedBundles(appBundles)
			}
			
			return self.apps.subtracting(oldApps)
		}
	}
	
	private func restoreCachedBundles() {
		guard let url = Self.cacheFileURL,
			  let data = try? Data(contentsOf: url),
			  let records = try? JSONDecoder().decode([CachedBundleRecord].self, from: data) else {
			return
		}
		let restoredBundles: [App.Bundle] = records.compactMap { record in
			guard let source = App.Source(rawValue: record.source),
				  FileManager.default.fileExists(atPath: record.filePath) else {
				return nil
			}
			let version = Version(versionNumber: record.versionNumber, buildNumber: record.buildNumber)
			return App.Bundle(
				version: version,
				name: record.name,
				bundleIdentifier: record.bundleIdentifier,
				fileURL: URL(fileURLWithPath: record.filePath),
				source: source
			)
		}
		guard !restoredBundles.isEmpty else { return }
		self.apps = Set(restoredBundles.map { bundle in
			App(
				bundle: bundle,
				update: nil,
				isIgnored: self.isIdentifierIgnored(bundle.bundleIdentifier),
				skippedVersion: self.skippedVersion(for: bundle.bundleIdentifier)
			)
		})
	}
	
	private func saveCachedBundles(_ bundles: Set<App.Bundle>) {
		guard let url = Self.cacheFileURL else { return }
		let records = bundles.map { bundle in
			CachedBundleRecord(
				versionNumber: bundle.version.versionNumber,
				buildNumber: bundle.version.buildNumber,
				name: bundle.name,
				bundleIdentifier: bundle.bundleIdentifier,
				filePath: bundle.fileURL.path,
				source: bundle.source.rawValue
			)
		}
		DispatchQueue.global(qos: .utility).async {
			guard let data = try? JSONEncoder().encode(records) else { return }
			try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			try? data.write(to: url, options: .atomic)
		}
	}
	
	/// Sets the given update for the given bundle and returns the combined object.
	func set(_ update: Result<App.Update, Error>?, for bundle: App.Bundle) -> App {
		self.updateQueue.sync {
			guard let oldApp = self.apps.first(where: { $0.bundle == bundle }) else {
				fatalError("App not in data store")
			}
			
			let app = App(bundle: bundle, update: update, isIgnored: oldApp.isIgnored, skippedVersion: oldApp.skippedVersion)
			self.update(app)
			
			return app
		}
	}
	
	/// Replaces an existing app entry in the data store with the given one.
	private func update(_ app: App) {
		if let oldApp = self.apps.first(where: { $0.identifier == app.identifier }) {
			self.apps.remove(oldApp)
		}
		
		self.apps.insert(app)
	}
	
	
	// MARK: - Ignoring Apps
	
	/// The key for storing a list of ignored apps.
	private static let IgnoredAppsKey = "IgnoredAppsKey"

	/// Returns whether the given identifier is marked as ignored.
	private func isIdentifierIgnored(_ identifier: String) -> Bool {
		return self.ignoredAppIdentifiers.contains(identifier)
	}
	
	/// Sets the ignored state of the given app.
	func setIgnoredState(_ ignored: Bool, for app: App) {
		var ignoredApps = self.ignoredAppIdentifiers
		
		if ignored {
			ignoredApps.insert(app.bundleIdentifier)
		} else {
			ignoredApps.remove(app.bundleIdentifier)
		}

		UserDefaults.standard.set(Array(ignoredApps), forKey: Self.IgnoredAppsKey)
		
		updateQueue.sync {
			self.update(app.with(ignoredState: ignored))
		}
	}
	
	/// Returns the identifiers of ignored apps.
	private var ignoredAppIdentifiers: Set<String> {
		return Set((UserDefaults.standard.array(forKey: Self.IgnoredAppsKey) as? [String]) ?? [])
	}
	
	/// The key for storing per-app skipped versions (`[bundleIdentifier: [versionNumber, buildNumber]]`).
	private static let SkippedAppVersionsKey = "SkippedAppVersionsKey"
	
	private func skippedVersion(for identifier: String) -> Version? {
		guard let dict = UserDefaults.standard.dictionary(forKey: Self.SkippedAppVersionsKey) as? [String: [String: String]],
			  let entry = dict[identifier] else {
			return nil
		}
		let versionNumber = entry["versionNumber"]?.isEmpty == false ? entry["versionNumber"] : nil
		let buildNumber = entry["buildNumber"]?.isEmpty == false ? entry["buildNumber"] : nil
		let version = Version(versionNumber: versionNumber, buildNumber: buildNumber)
		return version.isEmpty ? nil : version
	}
	
	func setSkippedVersion(_ version: Version?, for app: App) {
		var dict = (UserDefaults.standard.dictionary(forKey: Self.SkippedAppVersionsKey) as? [String: [String: String]]) ?? [:]
		if let version, !version.isEmpty {
			dict[app.bundleIdentifier] = [
				"versionNumber": version.versionNumber ?? "",
				"buildNumber": version.buildNumber ?? ""
			]
		} else {
			dict.removeValue(forKey: app.bundleIdentifier)
		}
		UserDefaults.standard.set(dict, forKey: Self.SkippedAppVersionsKey)
		
		updateQueue.sync {
			self.update(app.with(skippedVersion: version))
		}
	}

		
	// MARK: - Observer Handling
	
	/// A mapping of observers associated with apps.
	private var observers = [NSObject: ObserverHandler]()
	
	/// Adds the observer if it is not already registered.
	func addObserver(_ observer: NSObject, handler: @escaping ObserverHandler) {
		DispatchQueue.main.async {
			guard !self.observers.keys.contains(observer) else { return }
			self.observers[observer] = handler
				
			self.updateQueue.sync {
				// Call handler immediately to propagate initial state
				let apps = Array(self.apps)
				DispatchQueue.main.async {
					handler(apps)
				}
			}
		}
	}
	
	/// Removes the observer.
	func removeObserver(_ observer: NSObject) {
		DispatchQueue.main.async {
			self.observers.removeValue(forKey: observer)
		}
	}
		
	/// Notifies observers about state changes.
	private func notifyObservers(_ apps: [App]) {
		DispatchQueue.main.async {
			self.observers.forEach { (key: NSObject, handler: ObserverHandler) in
				handler(apps)
			}
		}
	}
		
}
