//
//  AppStoreCheckerOperationTest.swift
//  Latest Tests
//

import XCTest
@testable import Latest

final class AppStoreCheckerOperationTest: XCTestCase {

	func testStorefrontLanguageIdentifierUsesEnglishOverride() {
		let identifier = AppStoreUpdateCheckerOperation.storefrontLanguageIdentifier(preferredLanguages: ["en-HK"])
		XCTAssertEqual(identifier, "en_us")
	}

	func testStorefrontLanguageIdentifierUsesJapaneseOverride() {
		let identifier = AppStoreUpdateCheckerOperation.storefrontLanguageIdentifier(preferredLanguages: ["ja-JP"])
		XCTAssertEqual(identifier, "ja_jp")
	}

	func testStorefrontLanguageIdentifierSkipsUnsupportedLanguages() {
		let identifier = AppStoreUpdateCheckerOperation.storefrontLanguageIdentifier(preferredLanguages: ["zh-Hant-HK"])
		XCTAssertNil(identifier)
	}

	func testStorefrontLanguageIdentifierHandlesMissingPreference() {
		let identifier = AppStoreUpdateCheckerOperation.storefrontLanguageIdentifier(preferredLanguages: [])
		XCTAssertNil(identifier)
	}

}
