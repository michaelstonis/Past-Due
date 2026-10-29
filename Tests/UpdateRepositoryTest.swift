//
//  UpdateRepositoryTest.swift
//  LatestTests
//

import XCTest
@testable import Latest

final class UpdateRepositoryTest: XCTestCase {
	
	private func cask(_ token: String, name: String, version: String = "1.0", app: String? = nil, zap: [String] = [], minOS: String? = nil) -> String {
		var artifacts = [String]()
		if let app { artifacts.append("{\"app\":[\"\(app)\"]}") }
		if !zap.isEmpty { artifacts.append("{\"zap\":[{\"trash\":[\(zap.map { "\"\($0)\"" }.joined(separator: ","))]}]}") }
		let dependsOn: String
		if let minOS {
			dependsOn = "{\"macos\":{\">=\":[\"\(minOS)\"]}}"
		} else {
			dependsOn = "{}"
		}
		return "{\"token\":\"\(token)\",\"name\":[\"\(name)\"],\"version\":\"\(version)\",\"depends_on\":\(dependsOn),\"artifacts\":[\(artifacts.joined(separator: ","))]}"
	}
	
	private lazy var repository: UpdateRepository = {
		let json = "[" + [
			cask("zoom", name: "Zoom", app: "zoom.us.app", zap: ["~/Library/Preferences/us.zoom.xos.plist"]),
			cask("zoom-for-it-admins", name: "Zoom for IT Admins", app: "zoom.us.app", zap: ["~/Library/Preferences/us.zoom.xos.plist"]),
			cask("firefox", name: "Mozilla Firefox", version: "136.0", app: "Firefox.app", zap: ["~/Library/Preferences/org.mozilla.firefox.plist"]),
			cask("firefox@beta", name: "Mozilla Firefox Beta", version: "137.0b3", app: "Firefox.app", zap: ["~/Library/Preferences/org.mozilla.firefox.plist"]),
			cask("zed@preview", name: "Zed Preview", version: "0.180.0", app: "Zed Preview.app", zap: ["~/Library/Preferences/dev.zed.Zed-Preview.plist"]),
			cask("unversioned-app", name: "Unversioned App", version: "latest", app: "Unversioned.app", zap: ["~/Library/Preferences/com.example.unversioned.plist"]),
			cask("microsoft-word", name: "Microsoft Word", app: "Microsoft Word.app", zap: ["~/Library/Preferences/com.microsoft.Word.plist"]),
			cask("microsoft-office", name: "Microsoft Office", app: "Microsoft Word.app", zap: ["~/Library/Preferences/com.microsoft.Word.plist"]),
			cask("raindropio", name: "Raindrop.io", app: "Raindrop.io.app", zap: ["~/Library/Preferences/com.apple.Safari.plist"]),
			cask("prism", name: "Prism", app: "Prism.app", zap: ["~/Library/Preferences/com.example.prism.plist"]),
			cask("foo-tool", name: "Foo Tool", app: "Tool.app", zap: ["~/Library/Preferences/com.foobar.tool.plist"]),
			cask("wordpresscom-studio", name: "WordPress.com Studio", app: "Studio.app", zap: ["~/Library/Preferences/com.electron.studio.plist"]),
			cask("googledrive", name: "Google Drive", app: "Google Drive.app", zap: ["~/Library/Preferences/com.google.drivefs.plist"], minOS: "")
		].joined(separator: ",") + "]"
		let entries = (try? JSONDecoder().decode([FailableDecodable<UpdateRepository.Entry>].self, from: Data(json.utf8)).compactMap { $0.base }) ?? []
		return UpdateRepository(entries: entries)
	}()
	
	private func bundle(_ file: String, id: String) -> App.Bundle {
		App.Bundle(version: Version(versionNumber: "1", buildNumber: nil), name: file, bundleIdentifier: id, fileURL: URL(fileURLWithPath: "/Applications/\(file)"), source: .none)
	}
	
	func testMatchesRenamedAppByBundleIdentifier() {
		let entry = repository.entry(for: bundle("Google Drive 2.app", id: "com.google.drivefs"))
		XCTAssertEqual(entry?.token, "googledrive")
		XCTAssertNil(entry?.minimumOSVersion, "Empty minimumOSVersion string in cask JSON must decode safely to nil instead of throwing")
	}
	
	func testPrefersBaseCaskOverVariants() {
		XCTAssertEqual(repository.entry(for: bundle("zoom.us.app", id: "us.zoom.xos"))?.token, "zoom")
	}
	
	func testIgnoresBundleIdentifierWithoutNameResemblance() {
		XCTAssertNil(repository.entry(for: bundle("Safari.app", id: "com.apple.Safari")))
		XCTAssertNil(repository.entry(for: bundle("Notes Pro.app", id: "com.example.prism")))
	}
	
	func testRejectsGenericNameMatchWithConflictingIdentifiers() {
		XCTAssertNil(repository.entry(for: bundle("Studio.app", id: "com.BrickLink.Studio")))
	}
	
	func testVendorComparisonUsesWholeComponents() {
		// "com.foo" must not count as the vendor of "com.foobar".
		XCTAssertNil(repository.entry(for: bundle("Tool.app", id: "com.foo.tool")))
	}
	
	func testRejectsPrereleaseCaskForStableAppAndMatchesWhenChannelMatches() {
		// Stable Firefox.app must match "firefox", not "firefox@beta"
		XCTAssertEqual(repository.entry(for: bundle("Firefox.app", id: "org.mozilla.firefox"))?.token, "firefox")
		// Preview Zed Preview.app matches "zed@preview"
		XCTAssertEqual(repository.entry(for: bundle("Zed Preview.app", id: "dev.zed.Zed-Preview"))?.token, "zed@preview")
		// Stable Zed.app must not match "zed@preview"
		XCTAssertNil(repository.entry(for: bundle("Zed.app", id: "dev.zed.Zed")))
	}
	
	func testIgnoresUnversionedLatestCasks() {
		XCTAssertNil(repository.entry(for: bundle("Unversioned.app", id: "com.example.unversioned")))
	}
	
	func testBundleModificationDateIgnoresZipEpochAndPrefersNewerInfoPlistDate() throws {
		// Issue #21: Reproducible builds stamped with 1980-01-01 (1979-12-31 local) or stale outer .app directories
		// must resolve to the newer Contents/Info.plist modification date.
		let fm = FileManager.default
		let tempAppURL = fm.temporaryDirectory.appendingPathComponent("PastDueDateTest-\(UUID().uuidString).app", isDirectory: true)
		let contentsURL = tempAppURL.appendingPathComponent("Contents", isDirectory: true)
		let infoPlistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
		defer { try? fm.removeItem(at: tempAppURL) }
		
		try fm.createDirectory(at: contentsURL, withIntermediateDirectories: true)
		try Data("{}".utf8).write(to: infoPlistURL)
		
		// Set outer .app directory mtime to 1980-01-01 00:00:00 UTC (ZIP epoch -> 1979-12-31 in Americas)
		let zipEpoch = Date(timeIntervalSince1970: 315_532_800)
		let recentUpdateDate = Date(timeIntervalSinceNow: -3600)
		try fm.setAttributes([.modificationDate: zipEpoch], ofItemAtPath: tempAppURL.path)
		try fm.setAttributes([.modificationDate: recentUpdateDate], ofItemAtPath: infoPlistURL.path)
		
		let resolved = App.Bundle.resolveModificationDate(for: tempAppURL)
		XCTAssertEqual(resolved.timeIntervalSince1970, recentUpdateDate.timeIntervalSince1970, accuracy: 2.0)
	}
	
	func testSkippedVersionSuppressesCurrentUpdateUntilNewerVersionArrives() {
		// Issue #24: Skipping version 2.0 hides 2.0 update, but version 2.1 becomes available again.
		let localBundle = App.Bundle(
			version: Version(versionNumber: "1.0", buildNumber: nil),
			name: "Example",
			bundleIdentifier: "com.example.skip",
			fileURL: URL(fileURLWithPath: "/Applications/Example.app"),
			source: .sparkle
		)
		let remoteV2 = Version(versionNumber: "2.0", buildNumber: nil)
		let updateV2 = App.Update(app: localBundle, remoteVersion: remoteV2, minimumOSVersion: nil, source: .sparkle, date: nil, releaseNotes: nil, updateAction: .builtIn(block: { _ in }))
		
		let skippedApp = App(bundle: localBundle, update: .success(updateV2), isIgnored: false, skippedVersion: remoteV2)
		XCTAssertTrue(skippedApp.isCurrentUpdateSkipped)
		XCTAssertFalse(skippedApp.updateAvailable)
		
		let remoteV2_1 = Version(versionNumber: "2.1", buildNumber: nil)
		let updateV2_1 = App.Update(app: localBundle, remoteVersion: remoteV2_1, minimumOSVersion: nil, source: .sparkle, date: nil, releaseNotes: nil, updateAction: .builtIn(block: { _ in }))
		let newerApp = App(bundle: localBundle, update: .success(updateV2_1), isIgnored: false, skippedVersion: remoteV2)
		XCTAssertFalse(newerApp.isCurrentUpdateSkipped)
		XCTAssertTrue(newerApp.updateAvailable)
	}
	
	func testSupportRankAndAppInventoryExporterFormats() {
		// Issues #23 & #27: Verify support rank ordering and JSON/Markdown/CSV export output
		let sparkleBundle = App.Bundle(version: Version(versionNumber: "1.2", buildNumber: "12"), name: "Alpha", bundleIdentifier: "com.example.alpha", fileURL: URL(fileURLWithPath: "/Applications/Alpha.app"), source: .sparkle)
		let unsupportedBundle = App.Bundle(version: Version(versionNumber: "3.0", buildNumber: nil), name: "Beta", bundleIdentifier: "com.example.beta", fileURL: URL(fileURLWithPath: "/Applications/Beta.app"), source: .none)
		let app1 = App(bundle: sparkleBundle, update: nil, isIgnored: false)
		let app2 = App(bundle: unsupportedBundle, update: nil, isIgnored: false)
		
		XCTAssertEqual(AppListSnapshot.supportRank(for: app1), 0)
		XCTAssertEqual(AppListSnapshot.supportRank(for: app2), 2)
		
		let json = AppInventoryExporter.export(apps: [app2, app1], format: .json)
		XCTAssertTrue(json.contains("\"com.example.alpha\""))
		XCTAssertTrue(json.contains("\"Full\""))
		
		let markdown = AppInventoryExporter.export(apps: [app1, app2], format: .markdown)
		XCTAssertTrue(markdown.contains("| Alpha | `1.2` |"))
		
		let csv = AppInventoryExporter.export(apps: [app1, app2], format: .csv)
		XCTAssertTrue(csv.contains("Alpha,com.example.alpha,1.2,,false,sparkle,Full,/Applications/Alpha.app"))
	}
}
