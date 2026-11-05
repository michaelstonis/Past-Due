//
//  HomebrewUpdateOperation.swift
//  Latest
//

import Foundation

/// The operation updating apps or CLI formulae that are managed by Homebrew.
///
/// Only casks or formulae that Homebrew already manages are updated in-app. Apps that were installed in another way keep opening the app as before.
class HomebrewUpdateOperation: UpdateOperation, @unchecked Sendable {
	
	enum PackageKind {
		case cask
		case formula
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
	
	/// The arguments for upgrading either a cask or a formula.
	static func upgradeArguments(forToken token: String, kind: PackageKind) -> [String]? {
		guard isValid(caskToken: token) else { return nil }
		switch kind {
		case .cask:
			return ["upgrade", "--cask", "--greedy", token]
		case .formula:
			return ["upgrade", "--formula", token]
		}
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
	
	/// Discovers user-installed Homebrew CLI formulae (`installed_on_request == true` in `INSTALL_RECEIPT.json`) from Homebrew's `Cellar`.
	static func collectInstalledFormulaBundles(in cellars: [URL] = prefixes.map { URL(fileURLWithPath: $0).appendingPathComponent("Cellar") }) -> [App.Bundle] {
		guard brewURL != nil else { return [] }
		let fm = FileManager.default
		var results = [App.Bundle]()
		var seenTokens = Set<String>()
		
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
		return results
	}
	
	/// Extracts `desc`, `homepage`, and `sourceURL` from the formula's `.brew/<token>.rb` metadata file in `Cellar`.
	static func formulaMetadata(for bundle: App.Bundle) -> (description: String?, homepage: String?, sourceURL: String?) {
		guard let token = bundle.homebrewFormulaToken else { return (nil, nil, nil) }
		let fm = FileManager.default
		guard let versionURLs = try? fm.contentsOfDirectory(at: bundle.fileURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
			  let latestVersionURL = versionURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last else {
			return (nil, nil, nil)
		}
		let rbURL = latestVersionURL.appendingPathComponent(".brew/\(token).rb")
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
	
	/// Refreshes the cached Caskroom mapping and `brew outdated --json=v2` state once per update check pass.
	static func refreshOutdatedPackagesCache() {
		let freshMapping = caskroomAppMapping()
		var formulaeMap = [String: String]()
		var casksMap = [String: String]()
		
		if let brew = brewURL {
			let process = Process()
			process.executableURL = brew
			process.arguments = ["outdated", "--json=v2"]
			var env = ProcessInfo.processInfo.environment
			env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
			env["NONINTERACTIVE"] = "1"
			process.environment = env
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
		
		guard let brew = Self.brewURL, let arguments = Self.upgradeArguments(forToken: packageToken, kind: packageKind) else {
			finish(with: LatestError.custom(title: NSLocalizedString("HomebrewNotInstalledError", value: "Homebrew is not installed", comment: "Error title when an app should be updated through Homebrew, but Homebrew is missing."), description: nil))
			return
		}
		
		progressState = .installing
		let process = Process()
		process.executableURL = brew
		process.arguments = arguments
		
		var environment = ProcessInfo.processInfo.environment
		environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
		environment["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
		environment["NONINTERACTIVE"] = "1"
		process.environment = environment
		
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
