//
//  AppListSnapshot.swift
//  Latest
//
//  Created by Max Langer on 08.01.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

/// Describes the contents of the app list.
///
/// This structure supports the following states:
/// - All apps with updates available
/// - All installed apps, separated from the ones with updates through sections
/// - A filtered list of apps based on a given filter string
struct AppListSnapshot {
	
	/// The query after which apps can be filtered
	let filterQuery: String?
	
	/// The apps from which the content is created
	let apps: [App]
	
	/// Initializes the snapshot with the given list of apps and filter query.
	init(withApps apps: [App], filterQuery: String?) {
		self.filterQuery = filterQuery
		self.apps = apps
		let showExternal = AppListSettings.shared.includeAppsWithLimitedSupport
		let regularApps = apps.filter { !$0.isManagedByHomebrew }
		let homebrewApps = apps.filter { $0.isManagedByHomebrew && $0.isPackageSourceEnabled }
		self.entries = Self.generateEntries(from: regularApps, filterQuery: filterQuery)
		self.homebrewEntries = Self.generatePackageEntries(from: homebrewApps, filterQuery: filterQuery)
		self.regularAvailableUpdateCount = regularApps.filter { $0.updateAvailable && !$0.isIgnored && (showExternal || $0.usesBuiltInUpdater) }.count
		self.homebrewAvailableUpdateCount = homebrewApps.filter { $0.updateAvailable && !$0.isIgnored }.count
	}
	
	/// Returns a new snapshot containing an updated filter query.
	func updated(with filterQuery: String?) -> AppListSnapshot {
		return AppListSnapshot(withApps: self.apps, filterQuery: filterQuery)
	}
	
	/// Returns an updated snapshot.
	func updated() -> AppListSnapshot {
		return AppListSnapshot(withApps: self.apps, filterQuery: self.filterQuery)
	}
	
	/// The user-facable, sorted and filtered list of regular (non-Homebrew) apps and sections.
	let entries: [Entry]
	
	/// The user-facable, sorted and filtered list of Homebrew-managed apps/formulae and sections for the lower sidebar pane.
	let homebrewEntries: [Entry]
	
	/// Number of available updates in the upper regular Applications section.
	let regularAvailableUpdateCount: Int
	
	/// Number of available updates in the Homebrew section.
	let homebrewAvailableUpdateCount: Int
	
	/// Sorts and filters all available apps based on the given filter criteria.
	private static func generateEntries(from apps: [App], filterQuery: String?) -> [Entry] {
		// Mutable copy
		var visibleApps = apps
		
		visibleApps = visibleApps.filter { app in
			// Apply filter query
			if let filterQuery = filterQuery, !app.name.localizedCaseInsensitiveContains(filterQuery) {
				return false
			}

			// Filter installed updates
			if !AppListSettings.shared.showInstalledUpdates && !(app.updateAvailable || app.isIgnored) {
				return false
			}
						
			// Filter ignored apps
			if !AppListSettings.shared.showIgnoredUpdates && app.isIgnored {
				return false
			}

			// Filter unsupported apps
			if !AppListSettings.shared.includeUnsupportedApps && !app.supported {
				return false
			}
			
			// Filter apps not using the builtin updater
			if !AppListSettings.shared.includeAppsWithLimitedSupport && app.updateAvailable && !app.usesBuiltInUpdater {
				return false
			}
			
			return true
		}
		
		// Sort apps based on setting
		let filteredApps = visibleApps.sorted(by: { (app1, app2) -> Bool in
			switch AppListSettings.shared.sortOrder {
			case .updateDate:
				if app1.updateDate != app2.updateDate {
					return app1.updateDate > app2.updateDate
				}
			case .name:
				let lower1 = app1.name.lowercased()
				let lower2 = app2.name.lowercased()
				if lower1 != lower2 {
					return lower1 < lower2
				}
			case .supportState:
				let rank1 = Self.supportRank(for: app1)
				let rank2 = Self.supportRank(for: app2)
				if rank1 != rank2 {
					return rank1 < rank2
				}
				let lower1 = app1.name.lowercased()
				let lower2 = app2.name.lowercased()
				if lower1 != lower2 {
					return lower1 < lower2
				}
			}
			return app1.fileURL.path < app2.fileURL.path
		})
		
		// Build final list for the given subset of apps (Available Updates, Installed Apps, Ignored Apps)
		var availableUpdates = filteredApps.filter({ $0.updateAvailable && !$0.isIgnored }).map({ Entry.app($0) })
		if !availableUpdates.isEmpty {
			availableUpdates = [.section(Self.updatableAppsSection(withCount: availableUpdates.count))] + availableUpdates
		}
		
		var installedUpdates = filteredApps.filter({ !$0.updateAvailable && !$0.isIgnored }).map({ Entry.app($0) })
		if !installedUpdates.isEmpty {
			installedUpdates = [.section(Self.updatedAppsSection(withCount: installedUpdates.count))] + installedUpdates
		}
		
		var ignoredUpdates = filteredApps.filter({ $0.isIgnored }).map({ Entry.app($0) })
		if !ignoredUpdates.isEmpty {
			ignoredUpdates = [.section(Self.ignoredAppsSection(withCount: ignoredUpdates.count))] + ignoredUpdates
		}
		
		return availableUpdates + installedUpdates + ignoredUpdates
	}
	
	/// Builds the lower sidebar entries grouped by package manager source (`Homebrew`, `Node.js CLI (npm)`, `Python CLI (uv / pipx)`, `Rust CLI (Cargo)`, `MacPorts`, `Nix`),
	/// with available updates separated above installed packages within each source.
	private static func generatePackageEntries(from apps: [App], filterQuery: String?) -> [Entry] {
		let visibleApps = apps.filter { app in
			if let filterQuery = filterQuery, !app.name.localizedCaseInsensitiveContains(filterQuery) {
				return false
			}
			if !AppListSettings.shared.showInstalledUpdates && !(app.updateAvailable || app.isIgnored) {
				return false
			}
			if !AppListSettings.shared.showIgnoredUpdates && app.isIgnored {
				return false
			}
			return true
		}
		
		let orderedGroups: [String] = [
			"Homebrew",
			"Node.js CLI (npm)",
			"Python CLI (uv / pipx)",
			"Rust CLI (Cargo)",
			"MacPorts",
			"Nix"
		]
		
		var availableSections = [Entry]()
		var installedSections = [Entry]()
		var ignoredSections = [Entry]()
		
		for groupTitle in orderedGroups {
			let groupApps = visibleApps.filter { ($0.packageKind?.sectionTitle ?? "Homebrew") == groupTitle }
			guard !groupApps.isEmpty else { continue }
			
			let sorted = groupApps.sorted { app1, app2 in
				let lower1 = app1.name.lowercased()
				let lower2 = app2.name.lowercased()
				if lower1 != lower2 { return lower1 < lower2 }
				return app1.fileURL.path < app2.fileURL.path
			}
			
			let available = sorted.filter { $0.updateAvailable && !$0.isIgnored }
			if !available.isEmpty {
				let sectionTitle = "\(groupTitle) Updates"
				availableSections.append(.section(Section(title: sectionTitle, shortTitle: groupTitle, numberOfApps: available.count)))
				availableSections.append(contentsOf: available.map { Entry.app($0) })
			}
			
			let installed = sorted.filter { !$0.updateAvailable && !$0.isIgnored }
			if !installed.isEmpty {
				installedSections.append(.section(Section(title: groupTitle, shortTitle: groupTitle, numberOfApps: installed.count)))
				installedSections.append(contentsOf: installed.map { Entry.app($0) })
			}
			
			let ignored = sorted.filter { $0.isIgnored }
			if !ignored.isEmpty {
				ignoredSections.append(.section(Section(title: "\(groupTitle) (Ignored)", shortTitle: groupTitle, numberOfApps: ignored.count)))
				ignoredSections.append(contentsOf: ignored.map { Entry.app($0) })
			}
		}
		return availableSections + installedSections + ignoredSections
	}
	

	// MARK: - Accessors
	
	/// Returns the app at the given index in `entries`, if any.
	func app(at index: Int, inHomebrewSection: Bool = false) -> App? {
		let list = inHomebrewSection ? self.homebrewEntries : self.entries
		guard index >= 0 && index < list.count else { return nil }
		if case .app(let app) = list[index] {
			return app
		}
		
		return nil
	}
	
	func index(of app: App) -> Int? {
		return self.entries.firstIndex(where: { $0.isSimilar(to: .app(app)) })
	}
	
	func homebrewIndex(of app: App) -> Int? {
		return self.homebrewEntries.firstIndex(where: { $0.isSimilar(to: .app(app)) })
	}
	
	func contains(_ app: App) -> Bool {
		return self.apps.contains { $0.identifier == app.identifier }
	}
	
	/// Returns whether there is a section at the given index
	func isSectionHeader(at index: Int, inHomebrewSection: Bool = false) -> Bool {
		let list = inHomebrewSection ? self.homebrewEntries : self.entries
		guard index >= 0 && index < list.count else { return false }
		if case .section(_) = list[index] {
			return true
		}
		
		return false
	}
	
	
	// MARK: - Section Builder
	
	/// Ordering rank for `.supportState` sorting:
	/// 0 = Full built-in support (Sparkle, Mac App Store, or Caskroom/Formula-managed Homebrew)
	/// 1 = Limited support (Homebrew version tracking without in-app updater)
	/// 2 = Unsupported
	static func supportRank(for app: App) -> Int {
		switch app.supportState {
		case .full: return 0
		case .limited: return 1
		case .none: return 2
		}
	}
	
	private static func updatableAppsSection(withCount numberOfApps: Int) -> Section {
		let title = NSLocalizedString("AvailableUpdatesSection", comment: "Table Section Header for available updates")
		let shortTitle = NSLocalizedString("AvailableSection", comment: "Touch Bar section title for available updates")
		return Section(title: title, shortTitle: shortTitle, numberOfApps: numberOfApps)
	}
	
	private static func homebrewUpdatableAppsSection(withCount numberOfApps: Int) -> Section {
		let title = NSLocalizedString("HomebrewUpdatesSection", value: "Homebrew Updates", comment: "Table Section Header for available Homebrew Cask and Formula updates")
		let shortTitle = NSLocalizedString("HomebrewSection", value: "Homebrew", comment: "Touch Bar section title for Homebrew updates")
		return Section(title: title, shortTitle: shortTitle, numberOfApps: numberOfApps)
	}
	
	private static func updatedAppsSection(withCount numberOfApps: Int) -> Section {
		let title = NSLocalizedString("InstalledAppsSection", comment: "Table Section Header for already installed apps")
		let shortTitle = NSLocalizedString("InstalledSection", comment: "Touch Bar section title for installed apps")
		return Section(title: title, shortTitle: shortTitle, numberOfApps: numberOfApps)
	}

	private static func ignoredAppsSection(withCount numberOfApps: Int) -> Section {
		let title = NSLocalizedString("IgnoredAppsSection", comment: "Table Section Header for ignored apps")
		let shortTitle = NSLocalizedString("IgnoredSection", comment: "Touch Bar section title for ignored apps")
		return Section(title: title, shortTitle: shortTitle, numberOfApps: numberOfApps)
	}

}

extension AppListSnapshot {
	
	/// Defines one entry in the filtered update.
	enum Entry: Equatable, Hashable {
		
		/// Represents one app in the list.
		case app(App)
		
		/// Represents one section header in the list.
		case section(Section)
		
		func isSimilar(to entry: Entry) -> Bool {
			switch self {
			case .app(let app):
				if case .app(let other) = entry {
					return app.identifier == other.identifier
				}
			case .section(let section):
				if case .section(let other) = entry {
					return section.title == other.title
				}
			}
			
			return false
		}
		
	}
	
	/// A section used for grouping multiple results.
	struct Section: Equatable, Hashable {
		
		/// The title of the section.
		let title: String
		
		/// A shorter representation of the sections title.
		let shortTitle: String
		
		/// The number of apps this section encloses.
		let numberOfApps: Int
		
		
		// MARK: - Protocol Overrides
		
		/// Exclude the number of apps from the function
		static func ==(lhs: Section, rhs: Section) -> Bool {
			return lhs.title == rhs.title && lhs.numberOfApps == rhs.numberOfApps
		}
		
		/// Exclude the number of apps from the function
		func hash(into hasher: inout Hasher) {
			hasher.combine(title)
		}
		
	}
}

// MARK: - Installed App Inventory Exporter

/// Formats the discovered app inventory into JSON, Markdown, or CSV for export.
enum AppInventoryExporter {
	
	enum Format: String, CaseIterable {
		case json
		case markdown
		case csv
		
		var fileExtension: String {
			switch self {
			case .json: return "json"
			case .markdown: return "md"
			case .csv: return "csv"
			}
		}
		
		static func from(pathExtension: String) -> Format {
			switch pathExtension.lowercased() {
			case "md", "markdown": return .markdown
			case "csv": return .csv
			default: return .json
			}
		}
	}
	
	struct ExportedAppItem: Codable, Equatable {
		let name: String
		let bundleIdentifier: String
		let currentVersion: String
		let availableVersion: String?
		let updateAvailable: Bool
		let source: String
		let supportStatus: String
		let path: String
	}
	
	static func items(from apps: [App]) -> [ExportedAppItem] {
		let sorted = apps.sorted { a, b in
			let lower1 = a.name.lowercased()
			let lower2 = b.name.lowercased()
			if lower1 != lower2 { return lower1 < lower2 }
			return a.fileURL.path < b.fileURL.path
		}
		return sorted.map { app in
			let currentVersion = app.version.versionNumber ?? app.version.buildNumber ?? "Unknown"
			let availableVersion = app.updateAvailable ? (app.remoteVersion?.versionNumber ?? app.remoteVersion?.buildNumber) : nil
			let supportStatus: String
			switch AppListSnapshot.supportRank(for: app) {
			case 0: supportStatus = "Full"
			case 1: supportStatus = "Limited"
			default: supportStatus = "Unsupported"
			}
			return ExportedAppItem(
				name: app.name,
				bundleIdentifier: app.bundleIdentifier,
				currentVersion: currentVersion,
				availableVersion: availableVersion,
				updateAvailable: app.updateAvailable,
				source: app.source.rawValue,
				supportStatus: supportStatus,
				path: app.fileURL.path
			)
		}
	}
	
	static func export(apps: [App], format: Format) -> String {
		let records = items(from: apps)
		switch format {
		case .json:
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
			guard let data = try? encoder.encode(records), let string = String(data: data, encoding: .utf8) else {
				return "[]"
			}
			return string
		case .markdown:
			var lines = [
				"# Installed Applications",
				"",
				"| Name | Version | Available | Source | Support | Bundle ID | Path |",
				"| :--- | :--- | :--- | :--- | :--- | :--- | :--- |"
			]
			for item in records {
				let available = item.availableVersion ?? "—"
				lines.append("| \(escapeMarkdown(item.name)) | `\(escapeMarkdown(item.currentVersion))` | \(escapeMarkdown(available)) | \(escapeMarkdown(item.source)) | \(item.supportStatus) | `\(escapeMarkdown(item.bundleIdentifier))` | `\(escapeMarkdown(item.path))` |")
			}
			return lines.joined(separator: "\n") + "\n"
		case .csv:
			var lines = ["Name,Bundle Identifier,Current Version,Available Version,Update Available,Source,Support Status,Path"]
			for item in records {
				let row = [
					escapeCSV(item.name),
					escapeCSV(item.bundleIdentifier),
					escapeCSV(item.currentVersion),
					escapeCSV(item.availableVersion ?? ""),
					item.updateAvailable ? "true" : "false",
					escapeCSV(item.source),
					escapeCSV(item.supportStatus),
					escapeCSV(item.path)
				].joined(separator: ",")
				lines.append(row)
			}
			return lines.joined(separator: "\n") + "\n"
		}
	}
	
	private static func escapeMarkdown(_ value: String) -> String {
		value.replacingOccurrences(of: "|", with: "\\|")
	}
	
	private static func escapeCSV(_ value: String) -> String {
		if value.contains(",") || value.contains("\"") || value.contains("\n") {
			return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
		}
		return value
	}
}
