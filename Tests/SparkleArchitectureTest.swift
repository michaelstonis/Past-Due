//
//  SparkleArchitectureTest.swift
//  Latest Tests
//

import XCTest
import Sparkle
@testable import Latest

final class SparkleArchitectureTest: XCTestCase {

	// MARK: - Bundle Executable Architectures

	func testSupportedArchitecturesMapsExecutableArchitectureConstants() {
		let armOnly = Sparke.supportedArchitectures(from: [NSNumber(value: NSBundleExecutableArchitectureARM64)])
		XCTAssertEqual(armOnly, [.arm64])

		let intelOnly = Sparke.supportedArchitectures(from: [NSNumber(value: NSBundleExecutableArchitectureX86_64)])
		XCTAssertEqual(intelOnly, [.x86_64])

		let universal = Sparke.supportedArchitectures(from: [
			NSNumber(value: NSBundleExecutableArchitectureARM64),
			NSNumber(value: NSBundleExecutableArchitectureX86_64)
		])
		XCTAssertEqual(universal, [.arm64, .x86_64])

		let empty = Sparke.supportedArchitectures(from: nil)
		XCTAssertTrue(empty.isEmpty)
	}

	// MARK: - Feed URL Architecture Adaptation (Wireshark #454)

	func testAdaptFeedURLRewritesX86PathSegmentToArm64ForNativeArmApp() throws {
		let wiresharkIntelFeed = try XCTUnwrap(URL(string: "https://www.wireshark.org/update/0/Wireshark/4.4.5/macOS/x86-64/en-US/release.xml"))

		let adaptedForArm = Sparke.adaptFeedURL(
			wiresharkIntelFeed,
			bundleArchitectures: [.arm64],
			hostArchitecture: .arm64
		)
		XCTAssertEqual(
			adaptedForArm.absoluteString,
			"https://www.wireshark.org/update/0/Wireshark/4.4.5/macOS/arm64/en-US/release.xml"
		)

		let adaptedForUniversal = Sparke.adaptFeedURL(
			wiresharkIntelFeed,
			bundleArchitectures: [.arm64, .x86_64],
			hostArchitecture: .arm64
		)
		XCTAssertEqual(
			adaptedForUniversal.absoluteString,
			"https://www.wireshark.org/update/0/Wireshark/4.4.5/macOS/arm64/en-US/release.xml"
		)
	}

	func testAdaptFeedURLPreservesX86PathSegmentOnIntelHostOrIntelOnlyApp() throws {
		let wiresharkIntelFeed = try XCTUnwrap(URL(string: "https://www.wireshark.org/update/0/Wireshark/4.4.5/macOS/x86-64/en-US/release.xml"))

		let onIntelHost = Sparke.adaptFeedURL(
			wiresharkIntelFeed,
			bundleArchitectures: [.x86_64],
			hostArchitecture: .x86_64
		)
		XCTAssertEqual(onIntelHost, wiresharkIntelFeed)

		let intelOnlyAppOnArmHost = Sparke.adaptFeedURL(
			wiresharkIntelFeed,
			bundleArchitectures: [.x86_64],
			hostArchitecture: .arm64
		)
		XCTAssertEqual(intelOnlyAppOnArmHost, wiresharkIntelFeed)
	}

	func testAdaptFeedURLRewritesArm64PathSegmentToX86OnIntelHost() throws {
		let armFeed = try XCTUnwrap(URL(string: "https://www.wireshark.org/update/0/Wireshark/4.4.5/macOS/arm64/en-US/release.xml"))

		let adaptedForIntel = Sparke.adaptFeedURL(
			armFeed,
			bundleArchitectures: [.x86_64],
			hostArchitecture: .x86_64
		)
		XCTAssertEqual(
			adaptedForIntel.absoluteString,
			"https://www.wireshark.org/update/0/Wireshark/4.4.5/macOS/x86-64/en-US/release.xml"
		)
	}

	func testAdaptFeedURLDoesNotModifyFilenameSegment() throws {
		let filenameFeed = try XCTUnwrap(URL(string: "https://example.com/updates/x86_64.xml"))
		let adapted = Sparke.adaptFeedURL(
			filenameFeed,
			bundleArchitectures: [.arm64],
			hostArchitecture: .arm64
		)
		XCTAssertEqual(adapted, filenameFeed)
	}

	// MARK: - Enclosure URL Architecture Detection (Vorta #574 & Multi-Architecture Feeds)

	func testDetectsArm64EnclosureURLs() throws {
		let urls = [
			"https://github.com/borgbase/vorta/releases/download/v0.11.6/Vorta-v0.11.6-arm.dmg",
			"https://2.na.dl.wireshark.org/osx/Wireshark%204.4.5%20Arm%2064.dmg",
			"https://example.com/downloads/App-1.2.0-arm64.zip",
			"https://example.com/downloads/App-1.2.0-aarch64.dmg",
			"https://example.com/downloads/App-1.2.0-apple-silicon.dmg",
			"https://example.com/downloads/arm64/App-1.2.0.dmg"
		]

		for urlString in urls {
			let url = try XCTUnwrap(URL(string: urlString))
			XCTAssertEqual(Sparke.enclosureArchitecture(for: url), .arm64, "Expected .arm64 for \(urlString)")
		}
	}

	func testDetectsX86_64EnclosureURLs() throws {
		let urls = [
			"https://github.com/borgbase/vorta/releases/download/v0.11.6/Vorta-v0.11.6-intel.dmg",
			"https://2.na.dl.wireshark.org/osx/Wireshark%204.4.5%20Intel%2064.dmg",
			"https://example.com/downloads/App-1.2.0-x86_64.zip",
			"https://example.com/downloads/App-1.2.0-x86-64.zip",
			"https://example.com/downloads/App-1.2.0-x64.dmg",
			"https://example.com/downloads/App-1.2.0-amd64.dmg",
			"https://example.com/downloads/x86_64/App-1.2.0.dmg"
		]

		for urlString in urls {
			let url = try XCTUnwrap(URL(string: urlString))
			XCTAssertEqual(Sparke.enclosureArchitecture(for: url), .x86_64, "Expected .x86_64 for \(urlString)")
		}
	}

	func testDetectsUniversalEnclosureURLs() throws {
		let urls = [
			"https://example.com/downloads/App-1.2.0-universal.dmg",
			"https://example.com/downloads/App-1.2.0-universal2.zip",
			"https://example.com/downloads/App-1.2.0-arm64-x86_64.dmg"
		]

		for urlString in urls {
			let url = try XCTUnwrap(URL(string: urlString))
			XCTAssertEqual(Sparke.enclosureArchitecture(for: url), .universal, "Expected .universal for \(urlString)")
		}
	}

	func testAvoidsFalsePositivesOnSubstringsInAppNames() throws {
		let urls = [
			"https://example.com/downloads/Charm-1.2.0.dmg",
			"https://example.com/downloads/Alarm-2.0.zip",
			"https://example.com/downloads/Farmhouse-3.1.dmg",
			"https://example.com/downloads/IntellijPlugin-1.0.zip",
			"https://example.com/downloads/PastDue-1.0.0.dmg"
		]

		for urlString in urls {
			let url = try XCTUnwrap(URL(string: urlString))
			XCTAssertEqual(Sparke.enclosureArchitecture(for: url), .unspecified, "Expected .unspecified for \(urlString)")
		}
	}

	// MARK: - Compatibility Matrix

	func testRejectsArm64EnclosuresOnIntelHost() {
		XCTAssertFalse(
			Sparke.isArchitectureCompatible(
				enclosure: .arm64,
				bundleArchitectures: [.x86_64],
				hostArchitecture: .x86_64
			)
		)
		XCTAssertFalse(
			Sparke.isArchitectureCompatible(
				enclosure: .arm64,
				bundleArchitectures: [.arm64, .x86_64],
				hostArchitecture: .x86_64
			)
		)
		XCTAssertTrue(
			Sparke.isArchitectureCompatible(
				enclosure: .x86_64,
				bundleArchitectures: [.x86_64],
				hostArchitecture: .x86_64
			)
		)
		XCTAssertTrue(
			Sparke.isArchitectureCompatible(
				enclosure: .universal,
				bundleArchitectures: [.x86_64],
				hostArchitecture: .x86_64
			)
		)
		XCTAssertTrue(
			Sparke.isArchitectureCompatible(
				enclosure: .unspecified,
				bundleArchitectures: [.x86_64],
				hostArchitecture: .x86_64
			)
		)
	}

	func testRejectsX86_64EnclosuresForNativeArmAppsOnArm64Host() {
		// Native arm64 or Universal apps on an Apple Silicon Mac must not be replaced by x86_64-only builds
		XCTAssertFalse(
			Sparke.isArchitectureCompatible(
				enclosure: .x86_64,
				bundleArchitectures: [.arm64],
				hostArchitecture: .arm64
			)
		)
		XCTAssertFalse(
			Sparke.isArchitectureCompatible(
				enclosure: .x86_64,
				bundleArchitectures: [.arm64, .x86_64],
				hostArchitecture: .arm64
			)
		)

		// Strictly x86_64-only apps running under Rosetta may still receive x86_64 updates if no arm64 build exists
		XCTAssertTrue(
			Sparke.isArchitectureCompatible(
				enclosure: .x86_64,
				bundleArchitectures: [.x86_64],
				hostArchitecture: .arm64
			)
		)

		// Native arm64, universal, and unspecified builds are always compatible on arm64
		XCTAssertTrue(
			Sparke.isArchitectureCompatible(
				enclosure: .arm64,
				bundleArchitectures: [.arm64],
				hostArchitecture: .arm64
			)
		)
		XCTAssertTrue(
			Sparke.isArchitectureCompatible(
				enclosure: .universal,
				bundleArchitectures: [.arm64],
				hostArchitecture: .arm64
			)
		)
		XCTAssertTrue(
			Sparke.isArchitectureCompatible(
				enclosure: .unspecified,
				bundleArchitectures: [.arm64],
				hostArchitecture: .arm64
			)
		)
	}

	func testArchitecturePriorityPrefersNativeOverUniversalAndFallback() {
		XCTAssertGreaterThan(
			Sparke.architecturePriority(for: .arm64, hostArchitecture: .arm64),
			Sparke.architecturePriority(for: .universal, hostArchitecture: .arm64)
		)
		XCTAssertGreaterThan(
			Sparke.architecturePriority(for: .universal, hostArchitecture: .arm64),
			Sparke.architecturePriority(for: .unspecified, hostArchitecture: .arm64)
		)
		XCTAssertGreaterThan(
			Sparke.architecturePriority(for: .unspecified, hostArchitecture: .arm64),
			Sparke.architecturePriority(for: .x86_64, hostArchitecture: .arm64)
		)

		XCTAssertGreaterThan(
			Sparke.architecturePriority(for: .x86_64, hostArchitecture: .x86_64),
			Sparke.architecturePriority(for: .universal, hostArchitecture: .x86_64)
		)
		XCTAssertGreaterThan(
			Sparke.architecturePriority(for: .universal, hostArchitecture: .x86_64),
			Sparke.architecturePriority(for: .unspecified, hostArchitecture: .x86_64)
		)
	}

	func testAppcastItemCompatibilityChecksEnclosureURL() throws {
		let armItemDict: [String: Any] = [
			"title": "Version 0.11.6",
			"sparkle:version": "0.11.6",
			"enclosure": [
				"url": "https://github.com/borgbase/vorta/releases/download/v0.11.6/Vorta-v0.11.6-arm.dmg",
				"sparkle:version": "0.11.6",
				"length": "42971250",
				"type": "application/octet-stream"
			]
		]
		let armItem = try XCTUnwrap(SUAppcastItem(dictionary: armItemDict))

		XCTAssertFalse(
			Sparke.isAppcastItemCompatible(
				armItem,
				bundleArchitectures: [.x86_64],
				hostArchitecture: .x86_64
			),
			"ARM64 DMG must be rejected on Intel Macs even when sparkle:hardwareRequirements is omitted"
		)
		XCTAssertTrue(
			Sparke.isAppcastItemCompatible(
				armItem,
				bundleArchitectures: [.arm64],
				hostArchitecture: .arm64
			)
		)
	}

}
