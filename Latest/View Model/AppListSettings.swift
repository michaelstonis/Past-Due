//
//  AppListSettings.swift
//  Latest
//
//  Created by Max Langer on 09.01.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

private let SortOptionsKey = "SortOptionsKey"
private let ShowInstalledUpdatesKey = "ShowInstalledUpdatesKey"
private let ShowIgnoredUpdatesKey = "ShowIgnoredUpdatesKey"

private let IncludeUnsupportedAppsKey = "ShowUnsupportedUpdatesKey"
private let IncludeAppsWithLimitedSupportKey = "IncludeAppsWithLimitedSupportKey"
private let IncludeHomebrewUpdatesKey = "IncludeHomebrewUpdatesKey"
private let IncludeMacPortsUpdatesKey = "IncludeMacPortsUpdatesKey"
private let IncludeNixUpdatesKey = "IncludeNixUpdatesKey"
private let IncludeUVUpdatesKey = "IncludeUVUpdatesKey"
private let IncludeNPMUpdatesKey = "IncludeNPMUpdatesKey"
private let IncludeCargoUpdatesKey = "IncludeCargoUpdatesKey"
private let IncludeAdditionalPackageManagersKey = "IncludeAdditionalPackageManagersKey"

/// Observable front end to app list preferences.
struct AppListSettings: Observable {
	
	/// Sorting options available to the app list.
	enum SortOptions: Int, CaseIterable {
		/// Sort based on the date of the the last update, similar to what the App Store does.
		case updateDate = 0
		
		/// Sort alphabetically by app name.
		case name = 1
		
		/// Sort by update support level (Full Support, Limited Support, Unsupported).
		case supportState = 2
		
		/// A user-displayable text of the given sort option.
		var displayName: String {
			switch self {
			case .updateDate:
				return NSLocalizedString("DateSortOption", comment: "Update date sorting option. Displayed in menu with title: 'Sort By' -> 'Date'")
			case .name:
				return NSLocalizedString("NameSortOption", comment: "Sorting option to list by app names alphabetically. Displayed in menu with title: 'Sort By' -> 'Name'")
			case .supportState:
				return NSLocalizedString("SupportSortOption", value: "Support Status", comment: "Sorting option to group by support status. Displayed in menu with title: 'Sort By' -> 'Support Status'")
			}
		}
	}
	
	var observers = [UUID : ObservationHandler]()

	private init() {
		// Show installed updates, apps with limited support, and package managers by default
		UserDefaults.standard.register(defaults: [
			ShowInstalledUpdatesKey: true,
			IncludeAppsWithLimitedSupportKey: true,
			IncludeHomebrewUpdatesKey: true,
			IncludeMacPortsUpdatesKey: true,
			IncludeNixUpdatesKey: true,
			IncludeUVUpdatesKey: true,
			IncludeNPMUpdatesKey: true,
			IncludeCargoUpdatesKey: true,
			IncludeAdditionalPackageManagersKey: true
		])
	}
	
	static var shared: AppListSettings = {
		return AppListSettings()
	}()
	
	/// The order the app list should be shown in.
	var sortOrder: SortOptions {
		set {
			set(newValue.rawValue, forKey: SortOptionsKey)
		}
		
		get {
			SortOptions(rawValue: UserDefaults.standard.integer(forKey: SortOptionsKey)) ?? .updateDate
		}
	}
	
	/// Whether installed apps should be visible
	var showInstalledUpdates: Bool {
		set {
			set(newValue, forKey: ShowInstalledUpdatesKey)
		}
		
		get {
			UserDefaults.standard.bool(forKey: ShowInstalledUpdatesKey)
		}
	}
	
	/// Whether ignored apps should be visible
	var showIgnoredUpdates: Bool {
		set {
			set(newValue, forKey: ShowIgnoredUpdatesKey)
		}
		
		get {
			UserDefaults.standard.bool(forKey: ShowIgnoredUpdatesKey)
		}
	}
	
	/// Whether unsupported apps should be visible
	var includeUnsupportedApps: Bool {
		set {
			set(newValue, forKey: IncludeUnsupportedAppsKey)
		}
		
		get {
			UserDefaults.standard.bool(forKey: IncludeUnsupportedAppsKey)
		}
	}
	
	/// Whether apps only partially supported by Latest should be included.
	var includeAppsWithLimitedSupport: Bool {
		set {
			set(newValue, forKey: IncludeAppsWithLimitedSupportKey)
		}
		
		get {
			UserDefaults.standard.bool(forKey: IncludeAppsWithLimitedSupportKey)
		}
	}
	
	/// Whether Homebrew-managed packages (Casks and CLI Formulae) should be shown in the Homebrew section.
	var includeHomebrewUpdates: Bool {
		set {
			set(newValue, forKey: IncludeHomebrewUpdatesKey)
		}
		
		get {
			UserDefaults.standard.bool(forKey: IncludeHomebrewUpdatesKey)
		}
	}
	
	/// Whether MacPorts packages (`port`) should be shown in the left side panel.
	var includeMacPortsUpdates: Bool {
		set { set(newValue, forKey: IncludeMacPortsUpdatesKey) }
		get { UserDefaults.standard.bool(forKey: IncludeMacPortsUpdatesKey) }
	}
	
	/// Whether Nix profile packages (`nix profile`) should be shown in the left side panel.
	var includeNixUpdates: Bool {
		set { set(newValue, forKey: IncludeNixUpdatesKey) }
		get { UserDefaults.standard.bool(forKey: IncludeNixUpdatesKey) }
	}
	
	/// Whether Python CLI tools (`uv` / `pipx`) should be shown in the left side panel.
	var includeUVUpdates: Bool {
		set { set(newValue, forKey: IncludeUVUpdatesKey) }
		get { UserDefaults.standard.bool(forKey: IncludeUVUpdatesKey) }
	}
	
	/// Whether global Node.js CLI packages (`npm -g`) should be shown in the left side panel.
	var includeNPMUpdates: Bool {
		set { set(newValue, forKey: IncludeNPMUpdatesKey) }
		get { UserDefaults.standard.bool(forKey: IncludeNPMUpdatesKey) }
	}
	
	/// Whether Rust CLI crates (`cargo`) should be shown in the left side panel.
	var includeCargoUpdates: Bool {
		set { set(newValue, forKey: IncludeCargoUpdatesKey) }
		get { UserDefaults.standard.bool(forKey: IncludeCargoUpdatesKey) }
	}
	
	/// Convenience property that toggles or checks whether any additional package manager is enabled.
	var includeAdditionalPackageManagers: Bool {
		set {
			set(newValue, forKey: IncludeAdditionalPackageManagersKey)
			set(newValue, forKey: IncludeMacPortsUpdatesKey)
			set(newValue, forKey: IncludeNixUpdatesKey)
			set(newValue, forKey: IncludeUVUpdatesKey)
			set(newValue, forKey: IncludeNPMUpdatesKey)
			set(newValue, forKey: IncludeCargoUpdatesKey)
		}
		
		get {
			includeMacPortsUpdates || includeNixUpdates || includeUVUpdates || includeNPMUpdates || includeCargoUpdates
		}
	}
	
	
	// MARK: - Utilities
	
	private func set(_ value: Any, forKey key: String) {
		UserDefaults.standard.set(value, forKey: key)
		
		DispatchQueue.main.async {
			self.notify()
		}
	}
	
}
