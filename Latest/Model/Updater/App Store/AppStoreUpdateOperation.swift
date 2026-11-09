//
//  AppStoreUpdateOperation.swift
//  Latest
//
//  Created by Max Langer on 01.07.19.
//  Copyright © 2019 Max Langer. All rights reserved.
//

import CommerceKit
import StoreFoundation

/// The operation updating Mac App Store apps.
class AppStoreUpdateOperation: UpdateOperation, @unchecked Sendable {

	/// The purchase associated with the to be updated app.
	private var purchase: SSPurchase!

	/// The observer that observes the Mac App Store updater.
	private var observerIdentifier: CKDownloadQueueObserver?
	
	/// The app-store identifier for the related app.
	private let itemIdentifier: UInt64
	
	private let installURL: URL
	
	private var installerPackageURL: URL?

	init(bundleIdentifier: String, installURL: URL, appIdentifier: App.Bundle.Identifier, appStoreIdentifier: UInt64) {
		self.installURL = installURL
		self.itemIdentifier = appStoreIdentifier
		super.init(bundleIdentifier: bundleIdentifier, appIdentifier: appIdentifier)
	}
	
	static func prepareForUpdates() throws(InstallHelperError) {
		// Framework can download and install apps automatically, or fallback to mas-cli when installed
		if requiresManualInstallation {
			do {
				try InstallHelper.verifyAvailability()
			} catch let helperError {
				if resolvedMasExecutableURL() == nil {
					throw helperError
				}
			}
		}
	}
	
	/// Known search paths for `mas` (`mas-cli`).
	static let defaultMasSearchPaths: [String] = [
		"/opt/homebrew/bin/mas",
		"/usr/local/bin/mas",
		"/opt/local/bin/mas"
	]
	
	/// Returns the first executable `mas` binary URL found in `candidates`.
	static func resolvedMasExecutableURL(candidates: [String] = defaultMasSearchPaths, fileManager: FileManager = .default) -> URL? {
		for path in candidates where fileManager.isExecutableFile(atPath: path) {
			return URL(fileURLWithPath: path)
		}
		return nil
	}
	
	/// Command-line arguments passed to `mas` to upgrade a specific Mac App Store item identifier.
	static func masUpgradeArguments(forItemIdentifier itemIdentifier: UInt64) -> [String] {
		return ["upgrade", String(itemIdentifier)]
	}
	
	fileprivate static let requiresManualInstallation: Bool = {
		let version = ProcessInfo.processInfo.operatingSystemVersion
		
		return switch version.majorVersion {
		case 14:
			ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: 14, minorVersion: 8, patchVersion: 2))
		case 15:
			ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: 15, minorVersion: 7, patchVersion: 2))
		default:
			ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: 26, minorVersion: 1, patchVersion: 0))
		}
	}()
	
	
	// MARK: - Operation Overrides

	override func execute() {
		super.execute()
		
		// If manual installation is required, the privileged InstallHelper is not enabled, and mas-cli is installed,
		// use mas-cli directly.
		if Self.requiresManualInstallation,
		   (try? InstallHelper.verifyAvailability()) == nil,
		   let masURL = Self.resolvedMasExecutableURL() {
			self.performMasUpgrade(using: masURL, fallbackError: nil)
			return
		}
		
		// Construct purchase to receive update
		let purchase = SSPurchase(itemIdentifier: self.itemIdentifier, account: nil)
		CKPurchaseController.shared().perform(purchase, withOptions: 0) { [weak self] purchase, _, error, response in
			guard let self = self else { return }

			if let error = error {
				if let masURL = Self.resolvedMasExecutableURL() {
					self.performMasUpgrade(using: masURL, fallbackError: error)
				} else {
					self.finish(with: error)
				}
				return
			}

			if let downloads = response?.downloads, downloads.count > 0, let purchase = purchase {
				self.purchase = purchase
				self.observerIdentifier = CKDownloadQueue.shared().add(self)
			} else if let masURL = Self.resolvedMasExecutableURL() {
				self.performMasUpgrade(using: masURL, fallbackError: LatestError.updateInfoUnavailable)
			} else {
				self.finish(with: LatestError.updateInfoUnavailable)
			}
		}
	}
	
	private func performMasUpgrade(using masURL: URL, fallbackError: Error?) {
		self.progressState = .installing
		let itemID = self.itemIdentifier
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			guard let self, !self.isCancelled else {
				self?.finish()
				return
			}
			let process = Process()
			process.executableURL = masURL
			process.arguments = Self.masUpgradeArguments(forItemIdentifier: itemID)
			let pipe = Pipe()
			process.standardOutput = pipe
			process.standardError = pipe
			do {
				try process.run()
				process.waitUntilExit()
				if process.terminationStatus == 0 {
					self.finish()
				} else if let fallbackError {
					self.finish(with: fallbackError)
				} else {
					let data = pipe.fileHandleForReading.readDataToEndOfFile()
					let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "mas upgrade exited with status \(process.terminationStatus)"
					self.finish(with: NSError(domain: "LatestAppStoreMasErrorDomain", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message]))
				}
			} catch {
				self.finish(with: fallbackError ?? error)
			}
		}
	}
	
	override func cancel() {
		self.finish()
	}

	override func finish() {
		if let observerIdentifier = self.observerIdentifier {
			CKDownloadQueue.shared().remove(observerIdentifier)
		}

		super.finish()
	}

	
	// MARK: - Manual Installation
	
	/// Adds a link to the downloaded app store package to retrieve it at a later time.
	fileprivate static func snapshotAppStorePackage(at path: String) -> URL? {
		do {
			let packageURL = URL(fileURLWithPath: path)
			let fileManager = FileManager.default
			
			let hardLinkURL = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: packageURL, create: true).appending(path: packageURL.lastPathComponent, directoryHint: .notDirectory)
			try fileManager.linkItem(at: packageURL, to: hardLinkURL)
			
			return hardLinkURL
		} catch {
			return nil
		}
	}
}


// MARK: - Download Observer

extension AppStoreUpdateOperation: CKDownloadQueueObserver {

	func downloadQueue(_ downloadQueue: CKDownloadQueue!, statusChangedFor download: SSDownload!) {
		// Cancel download if the operation has been cancelled
		if self.isCancelled {
			download.cancel(withStoreClient: ISStoreClient(storeClientType: 0))
			self.finish()
			return
		}

		guard download.metadata.itemIdentifier == itemIdentifier, let status = download.status else {
			return
		}
		
		// Nothing left to do, we wait for the install failure
		guard self.installerPackageURL == nil else {
			return
		}
		
		if Self.requiresManualInstallation && status.percentComplete >= 0.8 {
			// Keep the installer alive by linking to it. Manual installation will follow once the automatic one failed.
			self.progressState = .extracting(progress: 0.2)
			self.installerPackageURL = Self.snapshotAppStorePackage(at: download.primaryAsset.downloadPath)
			self.progressState = .extracting(progress: 0.7)
		} else {
			switch status.activePhase.phaseType {
			case 0:
				self.progressState = .downloading(loadedSize: Int64(status.activePhase.progressValue), totalSize: Int64(status.activePhase.totalProgressValue))
			case 1:
				self.progressState = .extracting(progress: Double(status.activePhase.progressValue) / Double(status.activePhase.totalProgressValue))
			default:
				self.progressState = .initializing
			}
		}
	}

	func downloadQueue(_ downloadQueue: CKDownloadQueue!, changedWithRemoval download: SSDownload!) {
		guard download.metadata.itemIdentifier == self.purchase.itemIdentifier, let status = download.status else {
			return
		}

		// Installed successfully
		guard status.isFailed else {
			self.finish()
			return
		}
		
		// No manual installation possible, abort with error (or fallback to mas-cli if installed)
		let targetBundle = Bundle(url: self.installURL) ?? Bundle(identifier: bundleIdentifier)
		guard let installerPackageURL, let receiptData = download.metadata.receiptData, let bundle = targetBundle, let receiptURL = bundle.appStoreReceiptURL else {
			if let masURL = Self.resolvedMasExecutableURL() {
				self.performMasUpgrade(using: masURL, fallbackError: status.error)
			} else {
				self.finish(with: status.error)
			}
			return
		}
		
		Task { [weak self] in
			guard let self, !self.isCancelled else {
				self?.finish()
				return
			}
			
			self.progressState = .installing
			
			do {
				try await InstallHelper.shared.installPackage(at: installerPackageURL, targetURL: bundle.bundlePath, receiptData: receiptData, receiptURL: receiptURL)
				self.finish()
			} catch {
				if let masURL = Self.resolvedMasExecutableURL() {
					self.performMasUpgrade(using: masURL, fallbackError: error)
				} else {
					self.finish(with: error)
				}
			}
		}
	}

	func downloadQueue(_ downloadQueue: CKDownloadQueue!, changedWithAddition download: SSDownload!) {}

}

private extension ISStoreAccount {
	static var primaryAccount: ISStoreAccount? {
		var account: ISStoreAccount?
		
		let group = DispatchGroup()
		group.enter()
		
		let accountService: ISAccountService = ISServiceProxy.genericShared().accountService
		accountService.primaryAccount { (storeAccount: ISStoreAccount) in
			account = storeAccount
			group.leave()
		}
		
		_ = group.wait(timeout: .now() + 30)
		
		return account
	}
}

private extension SSPurchase {
	convenience init(itemIdentifier: UInt64, account: ISStoreAccount?) {
		self.init()

		let parameters: [String: Any] = [
			"productType": "C",
			"price": 0,
			"salableAdamId": itemIdentifier,
			"pg": "default",
			"appExtVrsId": 0,

			// is redownload, use existing functionality
			"pricingParameters": "STDRDL"
		]

		buyParameters =
			parameters.map { key, value in
				"\(key)=\(value)"
			}
			.joined(separator: "&")

		if let account = account {
			accountIdentifier = account.dsID
			appleID = account.identifier
		}

		let downloadMetadata = SSDownloadMetadata()
		downloadMetadata.kind = "software"
		downloadMetadata.itemIdentifier = itemIdentifier

		self.downloadMetadata = downloadMetadata
		self.itemIdentifier = itemIdentifier
	}
}

extension SSDownloadMetadata {
	/// Returns the app store receipt from the metadata.
	var receiptData: Data? {
		dictionary?["app-receipt"] as? Data
	}
}
