//
//  HomebrewUpdateOperation.swift
//  Latest
//

import Foundation

/// The operation updating apps or CLI formulae that are managed by Homebrew.
///
/// Only casks or formulae that Homebrew already manages are updated in-app. Apps that were installed in another way keep opening the app as before.
class HomebrewUpdateOperation: UpdateOperation, @unchecked Sendable {
	
	enum PackageKind: Equatable {
		case cask
		case formula
		case macports
		case nix
		case cargo
		case uvTool
		case npmGlobal
		
		var displayLabel: String {
			switch self {
			case .cask: return "Homebrew Cask"
			case .formula: return "Homebrew Formula (CLI)"
			case .macports: return "MacPorts Package"
			case .nix: return "Nix Profile Package"
			case .cargo: return "Cargo Crate (Rust CLI)"
			case .uvTool: return "uv / pipx Tool (Python CLI)"
			case .npmGlobal: return "npm Global Package (Node.js CLI)"
			}
		}
		
		var sectionTitle: String {
			switch self {
			case .cask, .formula: return "Homebrew"
			case .npmGlobal: return "Node.js CLI (npm)"
			case .uvTool: return "Python CLI (uv / pipx)"
			case .cargo: return "Rust CLI (Cargo)"
			case .macports: return "MacPorts"
			case .nix: return "Nix"
			}
		}
		
		func isEnabled(in settings: AppListSettings = .shared) -> Bool {
			switch self {
			case .cask, .formula: return settings.includeHomebrewUpdates
			case .npmGlobal: return settings.includeNPMUpdates
			case .uvTool: return settings.includeUVUpdates
			case .cargo: return settings.includeCargoUpdates
			case .macports: return settings.includeMacPortsUpdates
			case .nix: return settings.includeNixUpdates
			}
		}
	}
	
	/// Parses a `homebrewFormulaToken` string (which may be prefixed with `"macports:"`, `"nix:"`, `"cargo:"`, `"uv:"`, or `"npm:"`)
	/// into its `PackageKind` and raw package name.
	static func parsePackageToken(_ rawToken: String) -> (kind: PackageKind, name: String) {
		if let colon = rawToken.firstIndex(of: ":") {
			let prefix = String(rawToken[..<colon])
			let name = String(rawToken[rawToken.index(after: colon)...])
			switch prefix {
			case "macports": return (.macports, name)
			case "nix": return (.nix, name)
			case "cargo": return (.cargo, name)
			case "uv": return (.uvTool, name)
			case "npm": return (.npmGlobal, name)
			default: break
			}
		}
		return (.formula, rawToken)
	}
	
	/// The Homebrew cask or formula token.
	private let packageToken: String
	
	/// Whether this operation upgrades a GUI cask or a CLI formula.
	private let packageKind: PackageKind
	
	/// The running brew process, kept for cancellation.
	private var process: Process?
	
	init(bundleIdentifier: String, appIdentifier: App.Bundle.Identifier, caskToken: String, packageKind: PackageKind = .cask) {
		self.packageToken = caskToken
		self.packageKind = packageKind
		super.init(bundleIdentifier: bundleIdentifier, appIdentifier: appIdentifier)
	}
	
	
	// MARK: - Homebrew
	
	/// Where Homebrew is installed: Apple silicon or Intel default prefixes.
	static let prefixes = ["/opt/homebrew", "/usr/local"]
	
	/// The location of the brew executable, if Homebrew is installed.
	static var brewURL: URL? {
		prefixes.map { URL(fileURLWithPath: $0).appendingPathComponent("bin/brew") }
			.first { FileManager.default.isExecutableFile(atPath: $0.path) }
	}
	
	/// Whether the token is a valid Homebrew token and can safely be passed to brew.
	static func isValid(caskToken token: String) -> Bool {
		token.range(of: "^[a-z0-9][a-z0-9@._+-]*$", options: .regularExpression) != nil
	}
	
	/// Validates package names across Homebrew and non-Homebrew package managers (including scoped `@scope/pkg` npm names).
	static func isValid(packageName name: String, for kind: PackageKind) -> Bool {
		switch kind {
		case .cask, .formula:
			return isValid(caskToken: name)
		case .npmGlobal, .uvTool, .cargo, .macports, .nix:
			guard !name.contains("..") else { return false }
			return name.range(of: "^(@[a-zA-Z0-9._-]+/)?[a-zA-Z0-9@][a-zA-Z0-9@._+-]*$", options: .regularExpression) != nil
		}
	}
	
	/// Whether Homebrew already manages the cask. Homebrew keeps one folder per installed cask in its `Caskroom`.
	static func isInstalled(caskToken token: String, in caskrooms: [URL] = prefixes.map { URL(fileURLWithPath: $0).appendingPathComponent("Caskroom") }) -> Bool {
		guard isValid(caskToken: token) else { return false }
		return caskrooms.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent(token).path) }
	}
	
	/// Whether Latest can update the app through Homebrew.
	static func canUpdate(caskToken token: String) -> Bool {
		brewURL != nil && isInstalled(caskToken: token)
	}
	
	/// The arguments for upgrading the cask. `--greedy` includes apps that update themselves, which Latest lists as well.
	static func upgradeArguments(forCaskToken token: String) -> [String]? {
		upgradeArguments(forToken: token, kind: .cask)
	}
	
	/// The arguments for upgrading a package in its respective package manager.
	static func upgradeArguments(forToken token: String, kind: PackageKind) -> [String]? {
		let (_, cleanName) = parsePackageToken(token)
		guard isValid(packageName: cleanName, for: kind) else { return nil }
		switch kind {
		case .cask:
			return ["upgrade", "--cask", "--greedy", cleanName]
		case .formula:
			return ["upgrade", "--formula", cleanName]
		case .macports:
			return ["upgrade", cleanName]
		case .nix:
			return ["profile", "upgrade", cleanName]
		case .cargo:
			return ["install", cleanName]
		case .uvTool:
			return ["tool", "upgrade", cleanName]
		case .npmGlobal:
			return ["update", "-g", cleanName]
		}
	}
	
	/// Returns the human-readable CLI command used to upgrade `token` under `kind`.
	static func upgradeCommandString(forToken token: String, kind: PackageKind) -> String {
		let (_, cleanName) = parsePackageToken(token)
		switch kind {
		case .cask: return "brew upgrade --cask --greedy \(cleanName)"
		case .formula: return "brew upgrade --formula \(cleanName)"
		case .macports: return "port upgrade \(cleanName)"
		case .nix: return "nix profile upgrade \(cleanName)"
		case .cargo: return "cargo install \(cleanName)"
		case .uvTool: return "uv tool upgrade \(cleanName)"
		case .npmGlobal: return "npm update -g \(cleanName)"
		}
	}
	
	/// Resolves the executable URL for the given `PackageKind`.
	static func executableURL(for kind: PackageKind, fileManager: FileManager = .default) -> URL? {
		let candidates: [String]
		switch kind {
		case .cask, .formula:
			return brewURL
		case .macports:
			candidates = ["/opt/local/bin/port"]
		case .nix:
			candidates = ["/nix/var/nix/profiles/default/bin/nix", "/run/current-system/sw/bin/nix", "/usr/local/bin/nix"]
		case .cargo:
			let home = fileManager.homeDirectoryForCurrentUser.path
			candidates = ["\(home)/.cargo/bin/cargo", "/opt/homebrew/bin/cargo", "/usr/local/bin/cargo"]
		case .uvTool:
			let home = fileManager.homeDirectoryForCurrentUser.path
			candidates = ["\(home)/.local/bin/uv", "\(home)/.cargo/bin/uv", "/opt/homebrew/bin/uv", "/usr/local/bin/uv"]
		case .npmGlobal:
			candidates = ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"]
		}
		for path in candidates where fileManager.isExecutableFile(atPath: path) {
			return URL(fileURLWithPath: path)
		}
		return nil
	}
	
	
	// MARK: - Caskroom & Cellar Inspection
	
	private static let cacheLock = NSLock()
	private static var cachedCaskroomAppsByFilename: [String: String]?
	private static var cachedOutdatedFormulae = [String: String]()
	private static var cachedOutdatedCasks = [String: String]()
	
	/// Builds or returns a mapping from lowercased `.app` bundle filename (e.g. `"obs.app"`) to installed Caskroom token (e.g. `"obs"`).
	static func caskroomAppMapping(in caskrooms: [URL] = prefixes.map { URL(fileURLWithPath: $0).appendingPathComponent("Caskroom") }) -> [String: String] {
		let fm = FileManager.default
		var mapping = [String: String]()
		for caskroom in caskrooms {
			guard let tokenURLs = try? fm.contentsOfDirectory(at: caskroom, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
				continue
			}
			for tokenURL in tokenURLs {
				let token = tokenURL.lastPathComponent
				guard isValid(caskToken: token),
					  let versionURLs = try? fm.contentsOfDirectory(at: tokenURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
					continue
				}
				for versionURL in versionURLs {
					guard let itemURLs = try? fm.contentsOfDirectory(at: versionURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
						continue
					}
					for itemURL in itemURLs where itemURL.pathExtension.lowercased() == "app" {
						mapping[itemURL.lastPathComponent.lowercased()] = token
					}
				}
			}
		}
		return mapping
	}
	
	/// Returns the installed Caskroom token for the `.app` bundle at `url`, if it is managed in Homebrew's `Caskroom`.
	static func installedCaskToken(forAppAt url: URL) -> String? {
		cacheLock.lock()
		if cachedCaskroomAppsByFilename == nil {
			cachedCaskroomAppsByFilename = caskroomAppMapping()
		}
		let mapping = cachedCaskroomAppsByFilename ?? [:]
		cacheLock.unlock()
		
		let filename = url.lastPathComponent.lowercased()
		if let token = mapping[filename] {
			return token
		}
		// Also check normalized filename (e.g. "ClaudeBar.app" -> "claudebar") against Caskroom directories
		let normalizedCandidate = url.deletingPathExtension().lastPathComponent.lowercased().replacingOccurrences(of: " ", with: "-")
		if isInstalled(caskToken: normalizedCandidate) {
			return normalizedCandidate
		}
		return nil
	}
	
	/// Whether the `.app` bundle at `url` is managed in Homebrew's `Caskroom`.
	static func isAppAtURLInCaskroom(_ url: URL) -> Bool {
		brewURL != nil && installedCaskToken(forAppAt: url) != nil
	}
	
	/// Whether `bundle` is managed in Homebrew's `Caskroom`.
	static func isBundleInCaskroom(_ bundle: App.Bundle) -> Bool {
		isAppAtURLInCaskroom(bundle.fileURL)
	}
	
	/// Discovers user-installed Homebrew CLI formulae (`installed_on_request == true` in `INSTALL_RECEIPT.json`) from Homebrew's `Cellar`,
	/// plus packages from other installed package managers (`npm -g`, `uv`/`pipx`, `Cargo`, `MacPorts`, `Nix`).
	static func collectInstalledFormulaBundles(in cellars: [URL] = prefixes.map { URL(fileURLWithPath: $0).appendingPathComponent("Cellar") }) -> [App.Bundle] {
		let fm = FileManager.default
		var results = [App.Bundle]()
		var seenTokens = Set<String>()
		
		if brewURL != nil {
			for cellar in cellars {
				guard let formulaURLs = try? fm.contentsOfDirectory(at: cellar, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
					continue
				}
				for formulaURL in formulaURLs {
					let token = formulaURL.lastPathComponent
					guard isValid(caskToken: token), !seenTokens.contains(token),
						  let versionURLs = try? fm.contentsOfDirectory(at: formulaURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]),
						  !versionURLs.isEmpty else {
						continue
					}
					// Pick the latest installed version directory in Cellar/<token>/
					let sortedVersions = versionURLs.sorted { a, b in
						VersionParser.parse(combinedVersionNumber: a.lastPathComponent) < VersionParser.parse(combinedVersionNumber: b.lastPathComponent)
					}
					guard let latestVersionURL = sortedVersions.last else { continue }
					
					let receiptURL = latestVersionURL.appendingPathComponent("INSTALL_RECEIPT.json")
					guard let receiptData = try? Data(contentsOf: receiptURL),
						  let receiptJSON = (try? JSONSerialization.jsonObject(with: receiptData)) as? [String: Any],
						  (receiptJSON["installed_on_request"] as? Bool) == true else {
						continue
					}
					
					let installedVersionString = latestVersionURL.lastPathComponent
					let version = VersionParser.parse(combinedVersionNumber: installedVersionString)
					guard !version.isEmpty else { continue }
					
					let installTimestamp = (receiptJSON["time"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
					let modDate = installTimestamp ?? (try? latestVersionURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
					
					seenTokens.insert(token)
					results.append(
						App.Bundle(
							version: version,
							name: token,
							bundleIdentifier: "sh.brew.formula.\(token)",
							fileURL: formulaURL,
							source: .homebrew,
							homebrewFormulaToken: token,
							modificationDate: modDate
						)
					)
				}
			}
		}
		results.append(contentsOf: collectAdditionalPackageBundles())
		return results
	}
	
	/// Discovers installed packages from `npm -g`, `uv`/`pipx`, `Cargo` (`~/.cargo/.crates2.json`), `MacPorts`, and `Nix` profiles.
	static func collectAdditionalPackageBundles(fileManager fm: FileManager = .default) -> [App.Bundle] {
		var results = [App.Bundle]()
		let home = fm.homeDirectoryForCurrentUser
		
		// 1. Node.js Global CLI (npm -g: /opt/homebrew/lib/node_modules, /usr/local/lib/node_modules)
		if executableURL(for: .npmGlobal, fileManager: fm) != nil {
			var seenNPM = Set<String>()
			let nodeModulesRoots = prefixes.map { URL(fileURLWithPath: $0).appendingPathComponent("lib/node_modules") }
			for rootURL in nodeModulesRoots {
				guard let entries = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else {
					continue
				}
				var candidateDirs = [URL]()
				for entry in entries {
					if entry.lastPathComponent.hasPrefix("@") {
						if fm.fileExists(atPath: entry.appendingPathComponent("package.json").path) {
							candidateDirs.append(entry)
						} else if let scopedDirs = try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) {
							candidateDirs.append(contentsOf: scopedDirs)
						}
					} else {
						candidateDirs.append(entry)
					}
				}
				for pkgDir in candidateDirs {
					let pkgJSONURL = pkgDir.appendingPathComponent("package.json")
					guard let data = try? Data(contentsOf: pkgJSONURL),
						  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
						  let rawVer = json["version"] as? String else {
						continue
					}
					let name = (json["name"] as? String) ?? pkgDir.lastPathComponent
					// Skip bundled corepack/npm if desired? Keep user-visible packages; skip only internal corepack shim
					guard name != "corepack",
						  isValid(packageName: name, for: .npmGlobal),
						  !seenNPM.contains(name) else {
						continue
					}
					let version = VersionParser.parse(combinedVersionNumber: rawVer)
					guard !version.isEmpty else { continue }
					let modDate = try? pkgDir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
					seenNPM.insert(name)
					results.append(
						App.Bundle(
							version: version,
							name: name,
							bundleIdentifier: "com.npmjs.global.\(name)",
							fileURL: pkgDir,
							source: .homebrew,
							homebrewFormulaToken: "npm:\(name)",
							modificationDate: modDate
						)
					)
				}
			}
		}
		
		// 2. Python CLI Tools: uv (~/.local/share/uv/tools/<tool>) & pipx (~/.local/share/pipx/venvs/<tool>)
		let pythonToolRoots = [
			home.appendingPathComponent(".local/share/uv/tools"),
			home.appendingPathComponent(".local/share/pipx/venvs")
		]
		var seenUV = Set<String>()
		for toolsDir in pythonToolRoots {
			guard let toolDirs = try? fm.contentsOfDirectory(at: toolsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
				continue
			}
			for toolURL in toolDirs {
				let name = toolURL.lastPathComponent
				guard isValid(packageName: name, for: .uvTool), !seenUV.contains(name) else { continue }
				// Look for <name>-<version>.dist-info in lib/python*/site-packages/
				let libDir = toolURL.appendingPathComponent("lib")
				var foundVersion: Version?
				if let pyDirs = try? fm.contentsOfDirectory(at: libDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
				   let pyDir = pyDirs.first {
					let sitePackages = pyDir.appendingPathComponent("site-packages")
					if let entries = try? fm.contentsOfDirectory(at: sitePackages, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
						let normalizedPrefix = name.replacingOccurrences(of: "-", with: "_").lowercased() + "-"
						for entry in entries where entry.lastPathComponent.lowercased().hasPrefix(normalizedPrefix) && entry.lastPathComponent.hasSuffix(".dist-info") {
							let verPart = entry.lastPathComponent.dropFirst(normalizedPrefix.count).dropLast(".dist-info".count)
							let parsed = VersionParser.parse(combinedVersionNumber: String(verPart))
							if !parsed.isEmpty {
								foundVersion = parsed
								break
							}
						}
					}
				}
				guard let version = foundVersion else { continue }
				let modDate = try? toolURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
				seenUV.insert(name)
				results.append(
					App.Bundle(
						version: version,
						name: name,
						bundleIdentifier: "sh.astral.uv.\(name)",
						fileURL: toolURL,
						source: .homebrew,
						homebrewFormulaToken: "uv:\(name)",
						modificationDate: modDate
					)
				)
			}
		}
		
		// 3. Cargo (~/.cargo/.crates2.json)
		let cargoCratesURL = home.appendingPathComponent(".cargo/.crates2.json")
		if executableURL(for: .cargo, fileManager: fm) != nil,
		   let data = try? Data(contentsOf: cargoCratesURL),
		   let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
		   let installs = json["installs"] as? [String: Any] {
			let modDate = try? cargoCratesURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
			for key in installs.keys {
				// Key format: "<crate> <version> (<source>)"
				let parts = key.split(separator: " ")
				guard parts.count >= 2 else { continue }
				let name = String(parts[0])
				let rawVer = String(parts[1])
				guard isValid(packageName: name, for: .cargo) else { continue }
				let version = VersionParser.parse(combinedVersionNumber: rawVer)
				guard !version.isEmpty else { continue }
				results.append(
					App.Bundle(
						version: version,
						name: name,
						bundleIdentifier: "org.rust-lang.cargo.\(name)",
						fileURL: cargoCratesURL,
						source: .homebrew,
						homebrewFormulaToken: "cargo:\(name)",
						modificationDate: modDate
					)
				)
			}
		}
		
		// 4. MacPorts (/opt/local/var/macports/software/<port>/<version>_0)
		let macportsSoftware = URL(fileURLWithPath: "/opt/local/var/macports/software")
		if executableURL(for: .macports, fileManager: fm) != nil,
		   let portDirs = try? fm.contentsOfDirectory(at: macportsSoftware, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
			for portURL in portDirs {
				let name = portURL.lastPathComponent
				guard isValid(packageName: name, for: .macports),
					  let verDirs = try? fm.contentsOfDirectory(at: portURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]),
					  let latestURL = verDirs.last else { continue }
				let rawVer = latestURL.lastPathComponent.split(separator: "_").first.map(String.init) ?? latestURL.lastPathComponent
				let version = VersionParser.parse(combinedVersionNumber: rawVer)
				guard !version.isEmpty else { continue }
				let modDate = try? latestURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
				results.append(
					App.Bundle(
						version: version,
						name: name,
						bundleIdentifier: "org.macports.port.\(name)",
						fileURL: portURL,
						source: .homebrew,
						homebrewFormulaToken: "macports:\(name)",
						modificationDate: modDate
					)
				)
			}
		}
		
		// 5. Nix Profiles (~/.local/state/nix/profiles/profile/manifest.json, ~/.nix-profile/manifest.json)
		let nixManifests = [
			home.appendingPathComponent(".local/state/nix/profiles/profile/manifest.json"),
			home.appendingPathComponent(".nix-profile/manifest.json")
		]
		if executableURL(for: .nix, fileManager: fm) != nil {
			var seenNix = Set<String>()
			for manifestURL in nixManifests {
				guard let data = try? Data(contentsOf: manifestURL),
					  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
					  let elements = json["elements"] as? [String: Any] else {
					continue
				}
				let modDate = try? manifestURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
				for (pkgName, value) in elements {
					guard isValid(packageName: pkgName, for: .nix), !seenNix.contains(pkgName) else { continue }
					let dict = value as? [String: Any]
					let rawVer = (dict?["version"] as? String) ?? "1.0"
					let version = VersionParser.parse(combinedVersionNumber: rawVer)
					guard !version.isEmpty else { continue }
					seenNix.insert(pkgName)
					results.append(
						App.Bundle(
							version: version,
							name: pkgName,
							bundleIdentifier: "org.nixos.nix.\(pkgName)",
							fileURL: manifestURL,
							source: .homebrew,
							homebrewFormulaToken: "nix:\(pkgName)",
							modificationDate: modDate
						)
					)
				}
			}
		}
		
		return results
	}
	
	/// Extracts `description`, `homepage`, and `sourceURL` from the package's local metadata
	/// (`.brew/<token>.rb` for Homebrew formulae, `package.json` for `npm -g`, and `.dist-info/METADATA` for `uv`/`pipx`).
	static func formulaMetadata(for bundle: App.Bundle) -> (description: String?, homepage: String?, sourceURL: String?) {
		guard let rawToken = bundle.homebrewFormulaToken else { return (nil, nil, nil) }
		let parsed = parsePackageToken(rawToken)
		let fm = FileManager.default
		
		switch parsed.kind {
		case .npmGlobal:
			let pkgJSONURL = bundle.fileURL.appendingPathComponent("package.json")
			guard let data = try? Data(contentsOf: pkgJSONURL),
				  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
				return (nil, nil, nil)
			}
			let desc = json["description"] as? String
			let homepage = json["homepage"] as? String
			var repoURL: String?
			if let repoStr = json["repository"] as? String {
				repoURL = repoStr
			} else if let repoDict = json["repository"] as? [String: Any], let url = repoDict["url"] as? String {
				repoURL = url
			}
			return (desc, homepage, repoURL)
			
		case .uvTool:
			let libDir = bundle.fileURL.appendingPathComponent("lib")
			guard let pyDirs = try? fm.contentsOfDirectory(at: libDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
				  let pyDir = pyDirs.first else {
				return (nil, nil, nil)
			}
			let sitePackages = pyDir.appendingPathComponent("site-packages")
			guard let entries = try? fm.contentsOfDirectory(at: sitePackages, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
				return (nil, nil, nil)
			}
			let normalizedPrefix = parsed.name.replacingOccurrences(of: "-", with: "_").lowercased() + "-"
			guard let distInfo = entries.first(where: { $0.lastPathComponent.lowercased().hasPrefix(normalizedPrefix) && $0.lastPathComponent.hasSuffix(".dist-info") }),
				  let metadataText = try? String(contentsOf: distInfo.appendingPathComponent("METADATA"), encoding: .utf8) else {
				return (nil, nil, nil)
			}
			var desc: String?
			var homepage: String?
			var sourceURL: String?
			for rawLine in metadataText.components(separatedBy: .newlines) {
				if rawLine.isEmpty { break } // Stop at body after RFC822 headers
				if desc == nil, rawLine.hasPrefix("Summary: ") {
					desc = String(rawLine.dropFirst("Summary: ".count)).trimmingCharacters(in: .whitespaces)
				} else if homepage == nil, rawLine.hasPrefix("Home-page: ") {
					let val = String(rawLine.dropFirst("Home-page: ".count)).trimmingCharacters(in: .whitespaces)
					if val.lowercased() != "unknown" { homepage = val }
				} else if rawLine.hasPrefix("Project-URL: ") {
					let val = String(rawLine.dropFirst("Project-URL: ".count))
					if let httpRange = val.range(of: "https://") {
						let urlStr = String(val[httpRange.lowerBound...]).trimmingCharacters(in: .whitespaces)
						if homepage == nil { homepage = urlStr }
						if sourceURL == nil && urlStr.lowercased().contains("github.com/") {
							sourceURL = urlStr
						}
					}
				}
			}
			return (desc, homepage, sourceURL)
			
		default:
			guard let versionURLs = try? fm.contentsOfDirectory(at: bundle.fileURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
				  let latestVersionURL = versionURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last else {
				return (nil, nil, nil)
			}
			let rbURL = latestVersionURL.appendingPathComponent(".brew/\(parsed.name).rb")
			guard let contents = try? String(contentsOf: rbURL, encoding: .utf8) else {
				return (nil, nil, nil)
			}
			var desc: String?
			var homepage: String?
			var sourceURL: String?
			for rawLine in contents.components(separatedBy: .newlines) {
				let line = rawLine.trimmingCharacters(in: .whitespaces)
				if desc == nil, line.hasPrefix("desc \""), line.hasSuffix("\"") {
					desc = String(line.dropFirst(6).dropLast(1))
				} else if homepage == nil, line.hasPrefix("homepage \""), line.hasSuffix("\"") {
					homepage = String(line.dropFirst(10).dropLast(1))
				} else if sourceURL == nil, line.hasPrefix("url \""), let endQuote = line.dropFirst(5).firstIndex(of: "\"") {
					sourceURL = String(line.dropFirst(5)[..<endQuote])
				} else if sourceURL == nil, line.hasPrefix("head \""), let endQuote = line.dropFirst(6).firstIndex(of: "\"") {
					sourceURL = String(line.dropFirst(6)[..<endQuote])
				}
				if desc != nil && homepage != nil && sourceURL != nil { break }
			}
			return (desc, homepage, sourceURL)
		}
	}
	
	private struct BrewOutdatedResponse: Decodable {
		struct FormulaItem: Decodable {
			let name: String
			let current_version: String
			let pinned: Bool?
		}
		struct CaskItem: Decodable {
			let name: String
			let current_version: String
		}
		let formulae: [FormulaItem]?
		let casks: [CaskItem]?
	}
	
	/// Builds an environment dictionary with `/opt/homebrew/bin` and `/usr/local/bin` in `PATH` so shebang scripts like `npm` (`#!/usr/bin/env node`) work inside a macOS GUI app.
	private static func buildCLIEnvironment() -> [String: String] {
		var env = ProcessInfo.processInfo.environment
		let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
		let home = FileManager.default.homeDirectoryForCurrentUser.path
		env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:\(home)/.cargo/bin:/opt/local/bin:\(existingPath)"
		env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
		env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
		env["NONINTERACTIVE"] = "1"
		return env
	}
	
	/// Refreshes the cached Caskroom mapping and outdated package state (`brew outdated --json=v2`, `npm outdated -g --json`, and PyPI for `uv`/`pipx`) once per update check pass.
	static func refreshOutdatedPackagesCache() {
		let freshMapping = caskroomAppMapping()
		var formulaeMap = [String: String]()
		var casksMap = [String: String]()
		let cliEnv = buildCLIEnvironment()
		
		// 1. Homebrew (`brew outdated --json=v2`)
		if let brew = brewURL {
			let process = Process()
			process.executableURL = brew
			process.arguments = ["outdated", "--json=v2"]
			process.environment = cliEnv
			let outPipe = Pipe()
			process.standardOutput = outPipe
			process.standardError = Pipe()
			if (try? process.run()) != nil {
				let data = outPipe.fileHandleForReading.readDataToEndOfFile()
				process.waitUntilExit()
				if process.terminationStatus == 0,
				   let decoded = try? JSONDecoder().decode(BrewOutdatedResponse.self, from: data) {
					for f in decoded.formulae ?? [] where f.pinned != true {
						let shortName = f.name.split(separator: "/").last.map(String.init) ?? f.name
						formulaeMap[shortName] = f.current_version
					}
					for c in decoded.casks ?? [] {
						let shortName = c.name.split(separator: "/").last.map(String.init) ?? c.name
						casksMap[shortName] = c.current_version
					}
				}
			}
		}
		
		// 2. Node.js Global CLI (`npm outdated -g --json` — note: exits with code 1 when outdated packages exist)
		if let npmURL = executableURL(for: .npmGlobal) {
			let process = Process()
			process.executableURL = npmURL
			process.arguments = ["outdated", "-g", "--json"]
			process.environment = cliEnv
			let outPipe = Pipe()
			process.standardOutput = outPipe
			process.standardError = Pipe()
			if (try? process.run()) != nil {
				let data = outPipe.fileHandleForReading.readDataToEndOfFile()
				process.waitUntilExit()
				if !data.isEmpty,
				   let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
					for (pkgName, infoAny) in json {
						if let info = infoAny as? [String: Any],
						   let latest = info["latest"] as? String, !latest.isEmpty {
							formulaeMap["npm:\(pkgName)"] = latest
						}
					}
				}
			}
		}
		
		// 3. Python CLI (`uv` / `pipx` tools via PyPI JSON API)
		let additionalBundles = collectAdditionalPackageBundles()
		let uvBundles = additionalBundles.filter { ($0.homebrewFormulaToken ?? "").hasPrefix("uv:") }
		if !uvBundles.isEmpty {
			let group = DispatchGroup()
			let lock = NSLock()
			for bundle in uvBundles {
				guard let rawToken = bundle.homebrewFormulaToken else { continue }
				let (_, cleanName) = parsePackageToken(rawToken)
				guard let url = URL(string: "https://pypi.org/pypi/\(cleanName)/json") else { continue }
				group.enter()
				var request = URLRequest(url: url, timeoutInterval: 4.0)
				request.setValue("PastDue/1.0", forHTTPHeaderField: "User-Agent")
				URLSession.shared.dataTask(with: request) { data, _, _ in
					defer { group.leave() }
					guard let data,
						  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
						  let info = json["info"] as? [String: Any],
						  let latest = info["version"] as? String, !latest.isEmpty else {
						return
					}
					let parsedLatest = VersionParser.parse(combinedVersionNumber: latest)
					if parsedLatest > bundle.version {
						lock.lock()
						formulaeMap["uv:\(cleanName)"] = latest
						lock.unlock()
					}
				}.resume()
			}
			_ = group.wait(timeout: .now() + 5.0)
		}
		
		cacheLock.lock()
		cachedCaskroomAppsByFilename = freshMapping
		cachedOutdatedFormulae = formulaeMap
		cachedOutdatedCasks = casksMap
		cacheLock.unlock()
	}
	
	static func outdatedFormulaVersion(for token: String) -> Version? {
		cacheLock.lock()
		let raw = cachedOutdatedFormulae[token]
		cacheLock.unlock()
		guard let raw, !raw.isEmpty else { return nil }
		return VersionParser.parse(combinedVersionNumber: raw)
	}
	
	static func outdatedCaskVersion(for token: String) -> Version? {
		cacheLock.lock()
		let raw = cachedOutdatedCasks[token]
		cacheLock.unlock()
		guard let raw, !raw.isEmpty && raw.lowercased() != "latest" else { return nil }
		return VersionParser.parse(combinedVersionNumber: raw)
	}
	
	
	// MARK: - Operation Overrides
	
	override func execute() {
		super.execute()
		
		guard let executable = Self.executableURL(for: packageKind),
			  let arguments = Self.upgradeArguments(forToken: packageToken, kind: packageKind) else {
			finish(with: LatestError.custom(title: NSLocalizedString("HomebrewNotInstalledError", value: "Package manager is not installed", comment: "Error title when an app should be updated through Homebrew or another package manager, but the executable is missing."), description: nil))
			return
		}
		
		progressState = .installing
		let process = Process()
		process.executableURL = executable
		process.arguments = arguments
		process.environment = Self.buildCLIEnvironment()
		
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		self.process = process
		
		do {
			try process.run()
		} catch {
			finish(with: error)
			return
		}
		
		let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
		process.waitUntilExit()
		
		if isCancelled || process.terminationStatus == 0 {
			finish()
			if !isCancelled {
				DispatchQueue.main.async {
					UpdateCheckCoordinator.shared.refreshAfterHomebrewUpgrade()
				}
			}
		} else {
			finish(with: LatestError.custom(title: NSLocalizedString("HomebrewUpdateFailedError", value: "Homebrew could not update this app", comment: "Error title when updating an app through Homebrew failed."), description: String(output.suffix(600))))
		}
	}
	
	override func cancel() {
		process?.terminate()
		super.cancel()
	}
	
}
