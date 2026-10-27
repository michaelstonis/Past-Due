//
//  AppDirectoryStore.swift
//  Latest
//
//  Created by Max Langer on 05.07.24.
//  Copyright © 2024 Max Langer. All rights reserved.
//

import Foundation

/// Object that takes care of storing and observing application directories.
class AppDirectoryStore {
	
	typealias UpdateHandler = () -> Void
	private let defaults: UserDefaults
	private let customPathsObserver: NSKeyValueObservation?
	private let disabledPathsObserver: NSKeyValueObservation?

	/// Initializes the store with the given update handler.
	init(defaults: UserDefaults = .standard, updateHandler: @escaping UpdateHandler) {
		self.defaults = defaults
		customPathsObserver = defaults.observe(\.directoryPaths, changeHandler: { _, _ in
			updateHandler()
		})
		disabledPathsObserver = defaults.observe(\.disabledDirectoryPaths, changeHandler: { _, _ in
			updateHandler()
		})
	}
	
	
	// MARK: - URLs
	
	/// All configured directory URLs (both enabled and disabled), for display in Settings.
	var allURLs: [URL] {
		Self.defaultURLs + customURLs
	}
	
	/// The active (enabled) URLs to be scanned for applications.
	var URLs: [URL] {
		allURLs.filter { isEnabled($0) }
	}
	
	/// Set of default application directory URLs (`/Applications`, `~/Applications`).
	static let defaultURLs: [URL] = {
		let fileManager = FileManager.default
		let urls = [FileManager.SearchPathDomainMask.localDomainMask, .userDomainMask].flatMap { (domainMask) -> [URL] in
			return fileManager.urls(for: .applicationDirectory, in: domainMask)
		}
		
		return urls.filter { url -> Bool in
			return fileManager.fileExists(atPath: url.path)
		}
	}()

	/// User-definable URLs.
	private var customURLs: [URL] {
		get {
			guard let paths = defaults.directoryPaths else { return [] }
			
			return paths.map { path in
				URL(filePath: path, directoryHint: .isDirectory, relativeTo: nil)
			}
		}
		
		set {
			defaults.directoryPaths = newValue.map { $0.relativePath }
		}
	}
	
	/// Paths of directories that have been unchecked/disabled by the user.
	private var disabledPaths: Set<String> {
		get {
			Set(defaults.disabledDirectoryPaths ?? [])
		}
		set {
			defaults.disabledDirectoryPaths = Array(newValue).sorted()
		}
	}
			

	// MARK: - Actions
	
	/// Whether scanning is enabled for the given directory URL.
	func isEnabled(_ url: URL) -> Bool {
		!disabledPaths.contains(url.standardizedFileURL.path)
	}
	
	/// Enables or disables scanning for the given directory URL.
	func setEnabled(_ enabled: Bool, for url: URL) {
		var current = disabledPaths
		let key = url.standardizedFileURL.path
		if enabled {
			current.remove(key)
		} else {
			current.insert(key)
		}
		disabledPaths = current
	}
	
	/// Adds the given URL to the store.
	///
	/// This method does nothing if the URL already exists.
	func add(_ url: URL) {
		// Ignore adding the same URL multiple times
		guard !allURLs.contains(url) else { return }
		customURLs.append(url)
	}
	
	/// Removes the custom URL, if set.
	func remove(_ url: URL) {
		customURLs.removeAll(where: { $0 == url })
		setEnabled(true, for: url)
	}
	
	/// Whether the URL can be removed from the store.
	func canRemove(_ url: URL) -> Bool {
		customURLs.contains(url) && !Self.defaultURLs.contains(url)
	}
	
	/// Whether the url currently reachable.
	func isReachable(_ url: URL) -> Bool {
		(try? url.checkResourceIsReachable()) == true
	}
}

extension UserDefaults {
	private static let directoryPathsKey = "directoryPaths"
	private static let disabledDirectoryPathsKey = "disabledDirectoryPaths"
	
	@objc dynamic var directoryPaths: [String]? {
		get {
			stringArray(forKey: Self.directoryPathsKey)
		}
		set {
			setValue(newValue, forKey: Self.directoryPathsKey)
		}
	}
	
	@objc dynamic var disabledDirectoryPaths: [String]? {
		get {
			stringArray(forKey: Self.disabledDirectoryPathsKey)
		}
		set {
			setValue(newValue, forKey: Self.disabledDirectoryPathsKey)
		}
	}
}
														
													
