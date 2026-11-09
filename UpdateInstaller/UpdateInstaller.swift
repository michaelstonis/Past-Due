//
//  Installer.swift
//  Installer
//
//  Created by Max Langer on 06.01.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Foundation

/// The implementation of the install helper.
class UpdateInstaller: NSObject, UpdateInstallerProtocol {
	func performInstallation(ofPackageAt url: URL, targetURL: String, receiptData: Data, receiptURL: URL, reply: @escaping ((any Error)?) -> Void) {
		do {
			// Install app using unencoded filesystem paths (URL.path() defaults to percentEncoded: true,
			// which turns "NSIRD_Past Due_..." into "NSIRD_Past%20Due_..." and breaks /usr/sbin/installer).
			let packagePath = url.path(percentEncoded: false)
			let normalizedTarget = URL(fileURLWithPath: targetURL).path(percentEncoded: false)
			var (success, output) = try runInstaller(packagePath: packagePath, target: normalizedTarget)
			if !success && normalizedTarget != "/" {
				// Fallback to the root volume mount point if the package requires a volume target
				let fallbackResult = try runInstaller(packagePath: packagePath, target: "/")
				if fallbackResult.success {
					success = true
					output = fallbackResult.output
				}
			}
			guard success else {
				reply(NSError(domain: "LatestInstallerErrorDomain", code: 0, userInfo: [NSLocalizedDescriptionKey: output]))
				return
			}
			
			// Insert receipt
			let fileManager = FileManager.default
			let attributes: [FileAttributeKey: Any] = [.ownerAccountID: 0, .groupOwnerAccountID: 0, .posixPermissions: 0o755]
			let receiptPath = receiptURL.path(percentEncoded: false)
			
			if fileManager.fileExists(atPath: receiptPath) {
				try fileManager.removeItem(atPath: receiptPath)
			} else {
				try fileManager.createDirectory(at: receiptURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: attributes)
			}
			
			try receiptData.write(to: URL(fileURLWithPath: receiptPath), options: .atomic)
			try fileManager.setAttributes(attributes, ofItemAtPath: receiptPath)
		} catch {
			reply(error)
			return
		}
		
		// Cleanup
		let directory = url.deletingLastPathComponent()
		try? FileManager.default.removeItem(at: directory)
		
		// Install successful
		reply(nil)
	}
	
	private func runInstaller(packagePath: String, target: String) throws -> (success: Bool, output: String) {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/sbin/installer")
		process.arguments = ["-pkg", packagePath, "-target", target]
		
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		
		try process.run()
		process.waitUntilExit()
		
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		let success = (process.terminationStatus == 0)
		
		return (success, output)
	}
}
