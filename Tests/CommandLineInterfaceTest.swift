//
//  CommandLineInterfaceTest.swift
//  Latest Tests
//
//  Copyright © 2026 Max Langer. All rights reserved.
//

import XCTest
@testable import Latest

class CommandLineInterfaceTest: XCTestCase {

	func testShouldRunCLIDetection() {
		// Invoked via `past-due` symlink
		XCTAssertTrue(CommandLineInterface.shouldRunCLI(arguments: ["/usr/local/bin/past-due"]))
		XCTAssertTrue(CommandLineInterface.shouldRunCLI(arguments: ["past-due", "list"]))

		// Invoked via app bundle binary with CLI subcommands/flags
		XCTAssertTrue(CommandLineInterface.shouldRunCLI(arguments: ["/Applications/Past Due.app/Contents/MacOS/Past Due", "list"]))
		XCTAssertTrue(CommandLineInterface.shouldRunCLI(arguments: ["/Applications/Past Due.app/Contents/MacOS/Past Due", "outdated"]))
		XCTAssertTrue(CommandLineInterface.shouldRunCLI(arguments: ["/Applications/Past Due.app/Contents/MacOS/Past Due", "update"]))
		XCTAssertTrue(CommandLineInterface.shouldRunCLI(arguments: ["/Applications/Past Due.app/Contents/MacOS/Past Due", "--help"]))
		XCTAssertTrue(CommandLineInterface.shouldRunCLI(arguments: ["/Applications/Past Due.app/Contents/MacOS/Past Due", "-v"]))

		// Normal GUI / Xcode / XCTest launch arguments should NOT trigger CLI mode
		XCTAssertFalse(CommandLineInterface.shouldRunCLI(arguments: ["/Applications/Past Due.app/Contents/MacOS/Past Due"]))
		XCTAssertFalse(CommandLineInterface.shouldRunCLI(arguments: ["/Applications/Past Due.app/Contents/MacOS/Past Due", "-NSDocumentRevisionsDebugMode", "YES"]))
		XCTAssertFalse(CommandLineInterface.shouldRunCLI(arguments: ["/Applications/Past Due.app/Contents/MacOS/Past Due", "-XCTest", "All"]))
	}

	func testArgumentParsing() throws {
		// Default (no args) -> list
		let defaultOpts = try CommandLineInterface.parse(arguments: ["past-due"])
		XCTAssertEqual(defaultOpts.command, .list)
		XCTAssertFalse(defaultOpts.jsonOutput)
		XCTAssertFalse(defaultOpts.includeUpToDate)

		// list --all --json
		let listAllJSON = try CommandLineInterface.parse(arguments: ["past-due", "list", "--all", "--json"])
		XCTAssertEqual(listAllJSON.command, .list)
		XCTAssertTrue(listAllJSON.includeUpToDate)
		XCTAssertTrue(listAllJSON.jsonOutput)

		// update without targets defaults to updateAll = true
		let updateDefault = try CommandLineInterface.parse(arguments: ["past-due", "update"])
		XCTAssertEqual(updateDefault.command, .update(targets: [], updateAll: true))

		// update with specific targets
		let updateTargets = try CommandLineInterface.parse(arguments: ["past-due", "upgrade", "Firefox", "com.apple.dt.Xcode"])
		XCTAssertEqual(updateTargets.command, .update(targets: ["Firefox", "com.apple.dt.Xcode"], updateAll: false))

		// version and help flags
		XCTAssertEqual(try CommandLineInterface.parse(arguments: ["past-due", "--version"]).command, .version)
		XCTAssertEqual(try CommandLineInterface.parse(arguments: ["past-due", "-h"]).command, .help)

		// Unknown argument throws
		XCTAssertThrowsError(try CommandLineInterface.parse(arguments: ["past-due", "--unknown-flag"]))
		XCTAssertThrowsError(try CommandLineInterface.parse(arguments: ["past-due", "bogus-subcommand"]))
	}

	func testTableAndJSONFormatting() throws {
		XCTAssertEqual(CommandLineInterface.formatTable(entries: [], includeUpToDate: false), "No updates available.")
		XCTAssertEqual(CommandLineInterface.formatTable(entries: [], includeUpToDate: true), "No applications found.")

		let entry = CommandLineInterface.AppEntry(
			name: "SampleApp",
			bundleIdentifier: "com.example.SampleApp",
			path: "/Applications/SampleApp.app",
			installedVersion: "1.0",
			installedBuild: "100",
			latestVersion: "2.0",
			latestBuild: "200",
			source: "sparkle",
			updateAvailable: true,
			builtInUpdater: true
		)

		let table = CommandLineInterface.formatTable(entries: [entry])
		XCTAssertTrue(table.contains("NAME"))
		XCTAssertTrue(table.contains("SampleApp"))
		XCTAssertTrue(table.contains("com.example.SampleApp"))
		XCTAssertTrue(table.contains("1.0"))
		XCTAssertTrue(table.contains("2.0"))

		let json = try CommandLineInterface.formatJSON(entries: [entry])
		let decoded = try JSONDecoder().decode([CommandLineInterface.AppEntry].self, from: Data(json.utf8))
		XCTAssertEqual(decoded, [entry])
	}

	func testReleaseNotesFormattingStripsDuplicateTextLists() throws {
		let html = "<ul><li>First bullet</li><li>Second bullet</li></ul>"
		let data = try XCTUnwrap(html.data(using: .utf16))
		let raw = try XCTUnwrap(NSAttributedString(html: data, documentAttributes: nil))

		let controller = ReleaseNotesTextViewController()
		let formatted = controller.format(raw)

		XCTAssertTrue(formatted.string.contains("•\tFirst bullet"))
		formatted.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: formatted.length)) { value, _, _ in
			if let style = value as? NSParagraphStyle {
				XCTAssertTrue(style.textLists.isEmpty, "Paragraph style should not retain NSTextList markers when literal bullets are present")
				XCTAssertEqual(style.headIndent, 36.0)
			}
		}
	}

}
