//
//  AppUpdater.swift
//  Latest
//
//  Created by Max Langer on 15.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa

extension App {
	
	/// An object representing a single application that is available on the computer.
	class Bundle {
		
		typealias Identifier = URL
		
		/// The version currently present on the users computer
		let version: Version
		
		/// The display name of the app
		let name: String
		
		/// The unique identifier of the bundle, equal to the URL of the bundle.
		let identifier: Identifier
		
		/// The bundle identifier of the app.
		let bundleIdentifier: String
		
		/// The url of the app on the users computer
		let fileURL: URL
		
		/// The date the bundle was last modified.
		let modificationDate: Date
		
		/// The source of the bundle (App Store, Sparkle...)
		let source: Source
		
		init(version: Version, name: String, bundleIdentifier: String, fileURL: URL, source: Source) {
			self.version = version
			self.name = name
			self.identifier = fileURL
			self.bundleIdentifier = bundleIdentifier
			self.fileURL = fileURL
			self.source = source
			
			self.modificationDate = Self.resolveModificationDate(for: fileURL)
		}
		
		/// Computes the most accurate modification date for an `.app` bundle, accounting for in-place updaters
		/// (which touch `Contents/Info.plist` without updating the outer `.app` directory mtime) and reproducible
		/// archives stamped with the 1980-01-01 DOS/ZIP epoch (`1979-12-31` in Western Hemisphere timezones).
		static func resolveModificationDate(for bundleURL: URL) -> Date {
			// Ignore dates on or before 1980-01-02 00:00:00 UTC (reproducible build / ZIP epoch)
			let minimumPlausibleDate = Date(timeIntervalSince1970: 315_619_200)
			let maximumPlausibleDate = Date().addingTimeInterval(86_400)
			
			let bundleValues = try? bundleURL.resourceValues(forKeys: [.contentModificationDateKey, .addedToDirectoryDateKey])
			let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
			let infoPlistValues = try? infoPlistURL.resourceValues(forKeys: [.contentModificationDateKey])
			
			let modificationCandidates = [
				bundleValues?.contentModificationDate,
				infoPlistValues?.contentModificationDate
			].compactMap { $0 }.filter { $0 > minimumPlausibleDate && $0 <= maximumPlausibleDate }
			
			if let latestModification = modificationCandidates.max() {
				return latestModification
			}
			if let addedDate = bundleValues?.addedToDirectoryDate,
			   addedDate > minimumPlausibleDate && addedDate <= maximumPlausibleDate {
				return addedDate
			}
			return bundleValues?.contentModificationDate ?? Date.distantPast
		}


		// MARK: - Actions
		
		/// Opens the app and a given index
		func open() {
			// Open application asynchronously
			let configuration = NSWorkspace.OpenConfiguration()
			NSWorkspace.shared.open(self.fileURL, configuration: configuration, completionHandler: nil)
		}
		
		
		// MARK: - Secure Coding
		
		static var supportsSecureCoding: Bool {
			return true
		}
		
		required convenience init?(coder: NSCoder) {
			let versionNumber = coder.decodeObject(of: NSString.self, forKey: "versionNumber") as String?
			let buildNumber = coder.decodeObject(of: NSString.self, forKey: "buildNumber") as String?
			
			guard let name = coder.decodeObject(of: NSString.self, forKey: "name") as String?,
				  let bundleIdentifier = coder.decodeObject(of: NSString.self, forKey: "bundleIdentifier") as String?,
				  let fileURL = coder.decodeObject(of: NSURL.self, forKey: "fileURL") as URL?,
				  let rawSource = coder.decodeObject(of: NSString.self, forKey: "source") as String?, let source = Source(rawValue: rawSource) else { return nil }
			
			self.init(version: Version(versionNumber: versionNumber, buildNumber: buildNumber), name: name, bundleIdentifier: bundleIdentifier, fileURL: fileURL, source: source)
		}
		
		func encode(with coder: NSCoder) {
			coder.encode(self.version.versionNumber, forKey: "versionNumber")
			coder.encode(self.version.buildNumber, forKey: "buildNumber")
			coder.encode(self.name, forKey: "name")
			coder.encode(self.bundleIdentifier, forKey: "bundleIdentifier")
			coder.encode(self.fileURL, forKey: "fileURL")
			coder.encode(self.source.rawValue, forKey: "source")
		}
	}
	
}

extension App.Bundle: Equatable {
    /// Compares two apps on equality
    static func ==(lhs: App.Bundle, rhs: App.Bundle) -> Bool {
        return lhs.fileURL == rhs.fileURL
    }
}

extension App.Bundle: Hashable {
	func hash(into hasher: inout Hasher) {
		hasher.combine(self.identifier)
		hasher.combine(self.version)
	}
}

extension App.Bundle: CustomDebugStringConvertible {
	var debugDescription: String {
		return "\(name), \(version)"
	}
}

