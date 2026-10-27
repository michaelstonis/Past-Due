//
//  CommandLineInterface.swift
//  Latest
//
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit
import Foundation

/// Provides the `past-due` Command Line Interface (CLI) for listing and installing app updates from the terminal.
enum CommandLineInterface {
	
	/// Supported CLI commands.
	enum Command: Equatable {
		/// Lists available updates (or all scanned apps when `includeUpToDate` is `true`).
		case list
		
		/// Installs available updates for the specified targets (or all updatable apps).
		case update(targets: [String], updateAll: Bool)
		
		/// Prints the Past Due version and build number.
		case version
		
		/// Prints usage instructions.
		case help
	}
	
	/// Parsed CLI invocation options.
	struct Options: Equatable {
		var command: Command = .list
		var jsonOutput: Bool = false
		var includeUpToDate: Bool = false
		var builtInOnly: Bool = false
	}
	
	/// Errors raised while parsing CLI arguments.
	enum ParseError: LocalizedError, Equatable {
		case unknownArgument(String)
		
		var errorDescription: String? {
			switch self {
			case .unknownArgument(let arg):
				return "Unknown argument or option: '\(arg)'. Run 'past-due --help' for usage."
			}
		}
	}
	
	/// Serializable representation of an app and its update state for CLI table and JSON output.
	struct AppEntry: Codable, Equatable {
		let name: String
		let bundleIdentifier: String
		let path: String
		let installedVersion: String
		let installedBuild: String?
		let latestVersion: String?
		let latestBuild: String?
		let source: String
		let updateAvailable: Bool
		let builtInUpdater: Bool
		
		init(app: App) {
			self.name = app.name
			self.bundleIdentifier = app.bundleIdentifier
			self.path = app.fileURL.path
			self.installedVersion = app.version.versionNumber ?? app.version.buildNumber ?? "-"
			self.installedBuild = app.version.buildNumber
			self.latestVersion = app.remoteVersion?.versionNumber ?? app.remoteVersion?.buildNumber
			self.latestBuild = app.remoteVersion?.buildNumber
			self.source = app.source.rawValue
			self.updateAvailable = app.updateAvailable
			self.builtInUpdater = app.usesBuiltInUpdater
		}
		
		init(
			name: String,
			bundleIdentifier: String,
			path: String,
			installedVersion: String,
			installedBuild: String? = nil,
			latestVersion: String? = nil,
			latestBuild: String? = nil,
			source: String,
			updateAvailable: Bool,
			builtInUpdater: Bool
		) {
			self.name = name
			self.bundleIdentifier = bundleIdentifier
			self.path = path
			self.installedVersion = installedVersion
			self.installedBuild = installedBuild
			self.latestVersion = latestVersion
			self.latestBuild = latestBuild
			self.source = source
			self.updateAvailable = updateAvailable
			self.builtInUpdater = builtInUpdater
		}
	}
	
	/// Recognized CLI subcommands and top-level flags when invoked via the `Past Due` binary directly.
	private static let recognizedFirstArguments: Set<String> = [
		"list", "outdated", "check",
		"update", "upgrade",
		"version", "--version", "-v",
		"help", "--help", "-h"
	]
	
	/// Returns whether the current process invocation should run in headless CLI mode instead of launching the GUI.
	static func shouldRunCLI(arguments: [String]) -> Bool {
		guard let executablePath = arguments.first else {
			return false
		}
		
		let executableName = URL(fileURLWithPath: executablePath).lastPathComponent.lowercased()
		if executableName == "past-due" {
			return true
		}
		
		guard arguments.count > 1 else {
			return false
		}
		
		let firstArg = arguments[1].lowercased()
		return recognizedFirstArguments.contains(firstArg)
	}
	
	/// Parses raw command-line arguments (including `arguments[0]`) into structured `Options`.
	static func parse(arguments: [String]) throws -> Options {
		let args = Array(arguments.dropFirst())
		var options = Options()
		
		guard !args.isEmpty else {
			return options
		}
		
		var index = 0
		var subcommand: String?
		
		// Check if the first token is a subcommand
		let first = args[0].lowercased()
		if !first.hasPrefix("-") {
			subcommand = first
			index = 1
		}
		
		var targets = [String]()
		var updateAllFlag = false
		
		while index < args.count {
			let arg = args[index]
			switch arg {
			case "--json", "-j":
				options.jsonOutput = true
			case "--all", "-a":
				options.includeUpToDate = true
				updateAllFlag = true
			case "--built-in-only":
				options.builtInOnly = true
			case "--help", "-h":
				options.command = .help
				return options
			case "--version", "-v":
				options.command = .version
				return options
			default:
				if arg.hasPrefix("-") {
					throw ParseError.unknownArgument(arg)
				}
				targets.append(arg)
			}
			index += 1
		}
		
		switch subcommand {
		case nil, "list", "outdated", "check":
			if !targets.isEmpty {
				throw ParseError.unknownArgument(targets[0])
			}
			options.command = .list
		case "update", "upgrade":
			options.command = .update(targets: targets, updateAll: updateAllFlag || targets.isEmpty)
		case "version":
			options.command = .version
		case "help":
			options.command = .help
		case let unknown?:
			throw ParseError.unknownArgument(unknown)
		}
		
		return options
	}
	
	
	// MARK: - Output Formatting
	
	/// Formats a list of `AppEntry` items as a human-readable aligned table.
	static func formatTable(entries: [AppEntry], includeUpToDate: Bool = false) -> String {
		guard !entries.isEmpty else {
			return includeUpToDate ? "No applications found." : "No updates available."
		}
		
		let nameHeader = "NAME"
		let bundleHeader = "BUNDLE ID"
		let currentHeader = "INSTALLED"
		let latestHeader = "LATEST"
		let sourceHeader = "SOURCE"
		
		let nameWidth = max(nameHeader.count, entries.map(\.name.count).max() ?? 0)
		let bundleWidth = max(bundleHeader.count, entries.map(\.bundleIdentifier.count).max() ?? 0)
		let currentWidth = max(currentHeader.count, entries.map(\.installedVersion.count).max() ?? 0)
		let latestWidth = max(latestHeader.count, entries.map { ($0.latestVersion ?? "-").count }.max() ?? 0)
		
		func pad(_ text: String, to width: Int) -> String {
			let padding = max(0, width - text.count)
			return text + String(repeating: " ", count: padding)
		}
		
		var lines = [String]()
		lines.append("\(pad(nameHeader, to: nameWidth))  \(pad(bundleHeader, to: bundleWidth))  \(pad(currentHeader, to: currentWidth))  \(pad(latestHeader, to: latestWidth))  \(sourceHeader)")
		
		for entry in entries {
			let latest = entry.latestVersion ?? "-"
			let sourceLabel = entry.builtInUpdater ? entry.source : "\(entry.source) (manual)"
			lines.append("\(pad(entry.name, to: nameWidth))  \(pad(entry.bundleIdentifier, to: bundleWidth))  \(pad(entry.installedVersion, to: currentWidth))  \(pad(latest, to: latestWidth))  \(sourceLabel)")
		}
		
		return lines.joined(separator: "\n")
	}
	
	/// Formats a list of `AppEntry` items as pretty-printed JSON.
	static func formatJSON(entries: [AppEntry]) throws -> String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		let data = try encoder.encode(entries)
		return String(data: data, encoding: .utf8) ?? "[]"
	}
	
	/// Help text displayed for `past-due --help`.
	static var helpText: String {
		"""
		OVERVIEW: Check for and install macOS application updates from the command line.

		USAGE:
		  past-due [command] [options]

		COMMANDS:
		  list, outdated, check         List applications with available updates (default).
		  update, upgrade [<app> ...]   Install available updates for specified apps (or all updatable apps).
		  version                       Print the Past Due version and build number.
		  help                          Display this help message.

		OPTIONS:
		  -a, --all                     List all scanned applications (with 'list') or update all apps (with 'update').
		  --built-in-only               Only include updates that can be installed directly by Past Due.
		  -j, --json                    Format output as JSON.
		  -v, --version                 Print version information.
		  -h, --help                    Display this help message.

		EXAMPLES:
		  past-due list
		  past-due list --json
		  past-due update --all
		  past-due update "Wireshark" com.Figma.Desktop
		"""
	}
	
	/// Version text displayed for `past-due --version`.
	static var versionText: String {
		let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
		let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
		return "Past Due \(shortVersion) (\(buildVersion))"
	}
	
	
	// MARK: - Execution
	
	/// Runs the CLI with the given arguments and returns a process exit code.
	static func run(arguments: [String]) -> Int32 {
		let options: Options
		do {
			options = try parse(arguments: arguments)
		} catch {
			fputs("error: \(error.localizedDescription)\n", stderr)
			return 64 // EX_USAGE
		}
		
		switch options.command {
		case .help:
			print(helpText)
			return 0
		case .version:
			print(versionText)
			return 0
		case .list:
			return runList(options: options)
		case .update(let targets, let updateAll):
			return runUpdate(targets: targets, updateAll: updateAll, options: options)
		}
	}
	
	private static func performScanAndUpdateCheck() -> [App] {
		_ = NSApplication.shared
		NSApplication.shared.setActivationPolicy(.prohibited)
		
		var didFinish = false
		let token = NotificationCenter.default.addObserver(
			forName: UpdateCheckCoordinator.didFinishCheckingNotification,
			object: nil,
			queue: .main
		) { _ in
			didFinish = true
		}
		defer {
			NotificationCenter.default.removeObserver(token)
		}
		
		UpdateCheckCoordinator.shared.run()
		
		let deadline = Date(timeIntervalSinceNow: 180)
		while !didFinish && Date() < deadline {
			RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
		}
		
		return UpdateCheckCoordinator.shared.appProvider.allApps
	}
	
	private static func runList(options: Options) -> Int32 {
		let allApps = performScanAndUpdateCheck()
		let includeExternal = !options.builtInOnly && AppListSettings.shared.includeAppsWithLimitedSupport
		
		let filtered = allApps
			.filter { app in
				guard !app.isIgnored else { return false }
				if options.includeUpToDate {
					return AppListSettings.shared.includeUnsupportedApps || app.supported
				} else {
					guard app.updateAvailable else { return false }
					return includeExternal || app.usesBuiltInUpdater
				}
			}
			.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
			.map(AppEntry.init)
		
		if options.jsonOutput {
			if let json = try? formatJSON(entries: filtered) {
				print(json)
			}
		} else {
			print(formatTable(entries: filtered, includeUpToDate: options.includeUpToDate))
		}
		
		return 0
	}
	
	private static func runUpdate(targets: [String], updateAll: Bool, options: Options) -> Int32 {
		let allApps = performScanAndUpdateCheck()
		let availableApps = allApps
			.filter { $0.updateAvailable && !$0.isIgnored }
			.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		
		let selectedApps: [App]
		if updateAll && targets.isEmpty {
			selectedApps = availableApps.filter { $0.usesBuiltInUpdater }
		} else {
			let lowerTargets = Set(targets.map { $0.lowercased() })
			selectedApps = availableApps.filter { app in
				lowerTargets.contains(app.name.lowercased()) || lowerTargets.contains(app.bundleIdentifier.lowercased())
			}
			
			// Warn about any requested target that was not found among available updates
			for target in targets {
				let matched = selectedApps.contains {
					$0.name.caseInsensitiveCompare(target) == .orderedSame ||
					$0.bundleIdentifier.caseInsensitiveCompare(target) == .orderedSame
				}
				if !matched {
					fputs("warning: No available update found matching '\(target)'.\n", stderr)
				}
			}
		}
		
		let updatable = selectedApps.filter { $0.usesBuiltInUpdater }
		let manualOnly = selectedApps.filter { !$0.usesBuiltInUpdater }
		
		for app in manualOnly {
			fputs("note: '\(app.name)' does not support built-in unattended installation and must be updated within the app.\n", stderr)
		}
		
		guard !updatable.isEmpty else {
			if !options.jsonOutput {
				print("No directly installable updates available.")
			} else if let json = try? formatJSON(entries: []) {
				print(json)
			}
			return manualOnly.isEmpty ? 0 : 1
		}
		
		// Prepare App Store updates if needed
		if updatable.contains(where: { $0.bundle.source == .appStore }) {
			try? AppStoreUpdateOperation.prepareForUpdates()
		}
		
		final class CLIUpdateObserver: NSObject {
			var errors = [App.Bundle.Identifier: Error]()
		}
		let observer = CLIUpdateObserver()
		
		for app in updatable {
			if !options.jsonOutput {
				let targetVersion = app.remoteVersion?.versionNumber ?? app.remoteVersion?.buildNumber ?? "latest"
				print("Updating \(app.name) to \(targetVersion)...")
			}
			UpdateQueue.shared.addObserver(observer, to: app.identifier) { state in
				if case .error(let error) = state {
					observer.errors[app.identifier] = error
				}
			}
			app.performUpdate(isBulkUpdate: true)
		}
		
		// Allow operations to be enqueued and run to completion
		RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.2))
		let deadline = Date(timeIntervalSinceNow: 600)
		while UpdateQueue.shared.operationCount > 0 && Date() < deadline {
			RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
		}
		// Flush trailing main-queue observer notifications
		RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.2))
		
		for app in updatable {
			UpdateQueue.shared.removeObserver(observer, for: app.identifier)
		}
		
		var failedCount = 0
		for app in updatable {
			if let error = observer.errors[app.identifier] {
				failedCount += 1
				fputs("error: Failed to update \(app.name): \(error.localizedDescription)\n", stderr)
			} else if !options.jsonOutput {
				print("Updated \(app.name).")
			}
		}
		
		if options.jsonOutput, let json = try? formatJSON(entries: updatable.map(AppEntry.init)) {
			print(json)
		}
		
		return failedCount == 0 ? 0 : 1
	}
	
}

/// Installs the `past-due` symlink in `/usr/local/bin/past-due`.
enum CommandLineInstaller {
	
	static let defaultInstallURL = URL(fileURLWithPath: "/usr/local/bin/past-due")
	
	/// Whether `/usr/local/bin/past-due` points to the current app's executable.
	static var isInstalled: Bool {
		guard let executablePath = Bundle.main.executableURL?.path,
			  let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: defaultInstallURL.path) else {
			return false
		}
		return destination == executablePath
	}
	
	/// Installs `/usr/local/bin/past-due` pointing to the current app's executable, prompting for admin privileges if needed.
	static func install() throws {
		guard let executablePath = Bundle.main.executableURL?.path else {
			throw LatestError.updateInfoUnavailable
		}
		
		let binDir = defaultInstallURL.deletingLastPathComponent()
		let fileManager = FileManager.default
		
		// Try direct symlink creation first if /usr/local/bin is writable
		do {
			if !fileManager.fileExists(atPath: binDir.path) {
				try fileManager.createDirectory(at: binDir, withIntermediateDirectories: true)
			}
			if fileManager.fileExists(atPath: defaultInstallURL.path) || (try? fileManager.destinationOfSymbolicLink(atPath: defaultInstallURL.path)) != nil {
				try fileManager.removeItem(at: defaultInstallURL)
			}
			try fileManager.createSymbolicLink(atPath: defaultInstallURL.path, withDestinationPath: executablePath)
			return
		} catch {
			// Fall back to privileged installation via AppleScript
			let escapedExec = executablePath.replacingOccurrences(of: "'", with: "'\\''")
			let escapedLink = defaultInstallURL.path.replacingOccurrences(of: "'", with: "'\\''")
			let escapedDir = binDir.path.replacingOccurrences(of: "'", with: "'\\''")
			let scriptSource = "do shell script \"/bin/mkdir -p '\(escapedDir)' && /bin/ln -sf '\(escapedExec)' '\(escapedLink)'\" with administrator privileges"
			
			var errorInfo: NSDictionary?
			if let script = NSAppleScript(source: scriptSource) {
				script.executeAndReturnError(&errorInfo)
				if let errorInfo {
					let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Failed to install command line tool."
					throw LatestError.custom(title: "Could Not Install Command Line Tool", description: message)
				}
			}
		}
	}
	
}
