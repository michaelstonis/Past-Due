//
//  SparkleUpdateOperation.swift
//  Latest
//
//  Created by Max Langer on 01.07.19.
//  Copyright © 2019 Max Langer. All rights reserved.
//

import AppKit
import Sparkle

/// The operation updating Sparkle apps.
class SparkleUpdateOperation: UpdateOperation, @unchecked Sendable {
	
	/// The app bundle location discovered by Latest.
	private let bundleURL: URL
	
	/// The updater used to update this app.
	private var updater: SPUUpdater?
	
	// Callback to be called when the operation has been cancelled
	fileprivate var cancellationCallback: (() -> Void)?
	
	/// Pending throttled progress work item.
	private var pendingProgressWorkItem: DispatchWorkItem?
	
	/// Last time a download progress state update was emitted.
	private var lastProgressUpdateTime: TimeInterval = 0
	
	/// Initializes the operation with the given Sparkle app and handler
	init(bundleURL: URL, bundleIdentifier: String, appIdentifier: App.Bundle.Identifier) {
		self.bundleURL = bundleURL
		super.init(bundleIdentifier: bundleIdentifier, appIdentifier: appIdentifier)
	}
	
	
	// MARK: - Operation Overrides
	
	override func execute() {
		super.execute()
		
		// Gather app and app bundle
		guard let bundle = Bundle(path: self.bundleURL.path) else {
			self.finish(with: LatestError.updateInfoUnavailable)
			return
		}
		
		DispatchQueue.main.async {
			// Instantiate a new updater that performs the update
			let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: self, delegate: self)
			
			do {
				try updater.start()
			} catch let error {
				self.finish(with: error)
			}
			
			updater.checkForUpdates()
			
			self.updater = updater
		}
	}
	
	override func cancel() {
		super.cancel()
		
		self.cancellationCallback?()
		self.finish()
	}
	
	override func finish() {
		// Cleanup pending progress updates and updater
		self.pendingProgressWorkItem?.cancel()
		self.pendingProgressWorkItem = nil
		self.updater = nil
		
		super.finish()
	}
	
	
	// MARK: - Downloading
	
	/// The estimated total length of the downloaded app bundle.
	fileprivate var expectedContentLength: UInt64 = 0

	/// The length of already downloaded data.
	fileprivate var receivedLength: UInt64 = 0
	
	
	// MARK: - Installation
	
	/// Whether the app is open.
	fileprivate var isAppOpen = false
	
	/// One instance of the currently updating application.
	fileprivate var runningApplication: NSRunningApplication? {
		return NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == self.bundleIdentifier })
	}

}

// MARK: - Driver Implementation
extension SparkleUpdateOperation: SPUUserDriver {
	
	// MARK: - Preparing Update
	
	func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
		reply(.init(automaticUpdateChecks: false, sendSystemProfile: false))
	}
	
	func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
		self.progressState = .initializing
	}
	
	func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
		guard !self.isCancelled,
			  let bundle = Bundle(path: self.bundleURL.path),
			  Sparke.isAppcastItemCompatible(appcastItem, for: bundle) else {
			reply(.dismiss)
			if !self.isCancelled {
				self.finish(with: LatestError.updateInfoUnavailable)
			}
			return
		}
		reply(.install)
	}
		
	func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
		self.finish(with: error)
		acknowledgement()
	}
	
	func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
		self.finish(with: error)
		acknowledgement()
	}
	
	func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {		
		acknowledgement()
		self.finish()
	}
	
	func showUpdateInFocus() {
		// Noop
	}

	func showDownloadInitiated(cancellation: @escaping () -> Void) {
		if self.isCancelled {
			cancellation()
			return
		}

		self.cancellationCallback = cancellation
	}
	
	// MARK: - Downloading Update
	
	func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
		// This should be only called once per download. If it Uis called more than once, reset the progress
		self.expectedContentLength = expectedContentLength
		self.receivedLength = 0
		
		self.scheduleProgressHandler()
	}
	
	func showDownloadDidReceiveData(ofLength length: UInt64) {
		self.receivedLength += length

		// Expected content length may be wrong, adjust if needed
		self.expectedContentLength = max(self.expectedContentLength, self.receivedLength)
		
		self.scheduleProgressHandler()
	}
	
	private func scheduleProgressHandler() {
		let now = ProcessInfo.processInfo.systemUptime
		let elapsed = now - self.lastProgressUpdateTime
		
		if elapsed >= 0.25 {
			self.pendingProgressWorkItem?.cancel()
			self.pendingProgressWorkItem = nil
			self.lastProgressUpdateTime = now
			self.progressState = .downloading(loadedSize: Int64(self.receivedLength), totalSize: Int64(self.expectedContentLength))
		} else if self.pendingProgressWorkItem == nil {
			let workItem = DispatchWorkItem { [weak self] in
				guard let self, !self.isFinished, !self.isCancelled else { return }
				self.pendingProgressWorkItem = nil
				self.lastProgressUpdateTime = ProcessInfo.processInfo.systemUptime
				self.progressState = .downloading(loadedSize: Int64(self.receivedLength), totalSize: Int64(self.expectedContentLength))
			}
			self.pendingProgressWorkItem = workItem
			DispatchQueue.main.asyncAfter(deadline: .now() + (0.25 - elapsed), execute: workItem)
		}
	}

	
	// MARK: - Installing Update
	
	func showDownloadDidStartExtractingUpdate() {
		self.pendingProgressWorkItem?.cancel()
		self.pendingProgressWorkItem = nil
		self.progressState = .extracting(progress: 0)
	}
	
	func showExtractionReceivedProgress(_ progress: Double) {
		self.progressState = .extracting(progress: progress)
	}
	
	func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
		// Check whether app is open
		self.isAppOpen = self.runningApplication != nil
		
		reply(self.isCancelled ? .dismiss : .install)
	}
	
	func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
		self.progressState = .installing
	}
		

	// MARK: - Ignored Methods
	
	func showCanCheck(forUpdates canCheckForUpdates: Bool) {}
	func dismissUserInitiatedUpdateCheck() {}
	func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
	func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
	func showSendingTerminationSignal() {}
	func dismissUpdateInstallation() {}
	
}

extension SparkleUpdateOperation: SPUUpdaterDelegate {
	
	func feedURLString(for updater: SPUUpdater) -> String? {
		// We can try to supply a valid feed as addition to Sparkle's own methods.
		// For some cases (like DevMate) Sparkle fails to retrieve an appcast by itself.
		return Sparke.feedURL(from: updater.hostBundle)?.absoluteString
	}
	
	func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? {
		return Sparke.bestValidUpdate(in: appcast, for: updater.hostBundle)
	}
	
	func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
		guard Sparke.isAppcastItemCompatible(updateItem, for: updater.hostBundle) else {
			throw LatestError.updateInfoUnavailable
		}
	}
	
}
