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
	
	func testHomebrewSectionSeparationSupportStateAndInfoCard() {
		// Issue #28: Verify that Homebrew-managed updates (Caskroom & CLI Formulae) appear in their own
		// 'Homebrew Updates' section with '.full' support, while external catalog-only matches remain '.limited'
		// under 'Available Updates'.
		let sparkleBundle = App.Bundle(version: Version(versionNumber: "1.0", buildNumber: nil), name: "NativeApp", bundleIdentifier: "com.example.native", fileURL: URL(fileURLWithPath: "/Applications/NativeApp.app"), source: .sparkle)
		let sparkleUpdate = App.Update(app: sparkleBundle, remoteVersion: Version(versionNumber: "2.0", buildNumber: nil), minimumOSVersion: nil, source: .sparkle, date: nil, releaseNotes: nil, updateAction: .builtIn(block: { _ in }))
		let nativeApp = App(bundle: sparkleBundle, update: .success(sparkleUpdate), isIgnored: false)
		
		let externalBrewBundle = App.Bundle(version: Version(versionNumber: "1.0", buildNumber: nil), name: "WebApp", bundleIdentifier: "com.example.webapp", fileURL: URL(fileURLWithPath: "/Applications/WebApp.app"), source: .homebrew)
		let externalBrewUpdate = App.Update(app: externalBrewBundle, remoteVersion: Version(versionNumber: "2.0", buildNumber: nil), minimumOSVersion: nil, source: .homebrew, date: nil, releaseNotes: nil, updateAction: .external(label: "WebApp", block: { _ in }))
		let externalApp = App(bundle: externalBrewBundle, update: .success(externalBrewUpdate), isIgnored: false)
		
		let formulaBundle = App.Bundle(version: Version(versionNumber: "2.50.0", buildNumber: nil), name: "gh", bundleIdentifier: "sh.brew.formula.gh", fileURL: URL(fileURLWithPath: "/opt/homebrew/Cellar/gh"), source: .homebrew, homebrewFormulaToken: "gh")
		let formulaUpdate = App.Update(app: formulaBundle, remoteVersion: Version(versionNumber: "2.60.0", buildNumber: nil), minimumOSVersion: nil, source: .homebrew, date: nil, releaseNotes: nil, updateAction: .builtIn(block: { _ in }))
		let formulaApp = App(bundle: formulaBundle, update: .success(formulaUpdate), isIgnored: false)
		
		XCTAssertFalse(nativeApp.isManagedByHomebrew)
		XCTAssertEqual(nativeApp.supportState, .full)
		
		XCTAssertFalse(externalApp.isManagedByHomebrew)
		XCTAssertEqual(externalApp.supportState, .limited)
		
		XCTAssertTrue(formulaApp.isManagedByHomebrew)
		XCTAssertEqual(formulaApp.supportState, .full)
		
		let snapshot = AppListSnapshot(withApps: [nativeApp, formulaApp], filterQuery: nil)
		XCTAssertEqual(snapshot.entries.count, 2, "Expected 1 section header + 1 regular app in upper entries")
		XCTAssertEqual(snapshot.homebrewEntries.count, 2, "Expected 1 section header + 1 Homebrew app in lower homebrewEntries")
		XCTAssertEqual(snapshot.homebrewAvailableUpdateCount, 1)
		XCTAssertEqual(snapshot.app(at: 1, inHomebrewSection: false)?.identifier, nativeApp.identifier)
		XCTAssertEqual(snapshot.app(at: 1, inHomebrewSection: true)?.identifier, formulaApp.identifier)
		
		AppListSettings.shared.includeHomebrewUpdates = false
		let disabledSnapshot = AppListSnapshot(withApps: [nativeApp, formulaApp], filterQuery: nil)
		XCTAssertTrue(disabledSnapshot.homebrewEntries.isEmpty, "Expected lower homebrewEntries to be empty when includeHomebrewUpdates is false")
		XCTAssertEqual(disabledSnapshot.homebrewAvailableUpdateCount, 0)
		AppListSettings.shared.includeHomebrewUpdates = true
		
		let slug = HomebrewCheckerOperation.extractGitHubRepoSlug(from: [
			"https://cli.github.com/",
			"https://github.com/cli/cli/archive/refs/tags/v2.60.0.tar.gz"
		])
		XCTAssertEqual(slug, "cli/cli")
		
		let infoHTML = HomebrewCheckerOperation.formattedInfoCardHTML(
			name: "gh",
			token: "gh",
			kindLabel: "Homebrew Formula (CLI)",
			isManagedByHomebrew: true,
			installedVersion: Version(versionNumber: "2.50.0", buildNumber: nil),
			remoteVersion: Version(versionNumber: "2.60.0", buildNumber: nil),
			upgradeCommand: "brew upgrade --formula gh",
			description: "GitHub command-line tool",
			homepage: "https://cli.github.com/",
			caveats: "Run gh auth login",
			githubRepoSlug: slug,
			changelogHTML: "<ul><li>Added new workflow command</li></ul>"
		)
		XCTAssertTrue(infoHTML.contains("GitHub command-line tool"))
		XCTAssertTrue(infoHTML.contains("brew upgrade --formula gh"))
		XCTAssertTrue(infoHTML.contains("https://cli.github.com/"))
		XCTAssertTrue(infoHTML.contains("Run gh auth login"))
		XCTAssertTrue(infoHTML.contains("2.50.0 → 2.60.0"))
		XCTAssertTrue(infoHTML.contains("Added new workflow command"))
		XCTAssertTrue(infoHTML.contains("https://github.com/cli/cli/compare/v2.50.0...v2.60.0"))
		
		XCTAssertEqual(HomebrewUpdateOperation.upgradeArguments(forToken: "gh", kind: .formula), ["upgrade", "--formula", "gh"])
		XCTAssertEqual(HomebrewUpdateOperation.upgradeArguments(forToken: "firefox", kind: .cask), ["upgrade", "--cask", "--greedy", "firefox"])
	}

	func testStartupCacheRestoredAppsRemainUncheckedUntilInitialCheckRuns() {
		let store = AppDataStore()
		let cachedBundle = App.Bundle(version: Version(versionNumber: "1.0", buildNumber: "1"), name: "CachedApp", bundleIdentifier: "com.example.cached", fileURL: URL(fileURLWithPath: "/Applications/CachedApp.app"), source: .sparkle)
		let newlyAddedBundle = App.Bundle(version: Version(versionNumber: "2.0", buildNumber: "1"), name: "NewApp", bundleIdentifier: "com.example.new", fileURL: URL(fileURLWithPath: "/Applications/NewApp.app"), source: .sparkle)
		
		// Simulate startup cache restoration (apps loaded with update == nil)
		_ = store.set(appBundles: [cachedBundle])
		XCTAssertTrue(store.allApps.allSatisfy { !$0.hasBeenChecked })
		
		// Simulate initial directory scan completing where 1 new bundle was added since the cache was saved
		let newApps = store.set(appBundles: [cachedBundle, newlyAddedBundle])
		XCTAssertEqual(newApps.count, 1, "Only the newly added bundle is in newApps")
		
		// Including uncheckedBundles ensures the cache-restored bundle is ALSO checked on startup
		let uncheckedBundles = store.allApps.filter { !$0.hasBeenChecked }.map { $0.bundle }
		let changedOrUnchecked = Set(newApps.map { $0.bundle }).union(uncheckedBundles)
		XCTAssertEqual(changedOrUnchecked.count, 2, "Both cached and newly added bundles must be checked on startup")
	}
}
