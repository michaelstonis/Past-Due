//
//  Sparkle.swift
//  Latest
//
//  Created by Max Langer on 23.04.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

import Foundation
import Sparkle

struct Sparke {
	
	/// Supported CPU architectures for macOS app bundles.
	enum CPUArchitecture: String, Equatable, Hashable, CaseIterable {
		case arm64
		case x86_64
	}
	
	/// CPU architecture inferred from an appcast enclosure URL or filename.
	enum EnclosureArchitecture: Equatable {
		case arm64
		case x86_64
		case universal
		case unspecified
	}
	
	/// The CPU architecture of the host Mac running Past Due.
	static var hostArchitecture: CPUArchitecture {
		#if arch(arm64)
		return .arm64
		#else
		return .x86_64
		#endif
	}
	
	/// Returns the CPU architectures supported by the given app bundle's executable.
	static func supportedArchitectures(for bundle: Bundle) -> Set<CPUArchitecture> {
		return supportedArchitectures(from: bundle.executableArchitectures)
	}
	
	/// Maps `Bundle.executableArchitectures` constants to `CPUArchitecture` values.
	static func supportedArchitectures(from executableArchitectures: [NSNumber]?) -> Set<CPUArchitecture> {
		guard let executableArchitectures else { return [] }
		var architectures = Set<CPUArchitecture>()
		for arch in executableArchitectures {
			switch arch.intValue {
			case NSBundleExecutableArchitectureARM64:
				architectures.insert(.arm64)
			case NSBundleExecutableArchitectureX86_64:
				architectures.insert(.x86_64)
			default:
				break
			}
		}
		return architectures
	}
	
	/// Returns the Sparkle feed url for the app at the given URL, if available, adapted for the target CPU architecture.
	static func feedURL(from bundle: Bundle, hostArchitecture: CPUArchitecture = Self.hostArchitecture) -> URL? {
		guard let information = bundle.infoDictionary, let identifier = bundle.bundleIdentifier else {
			return nil
		}

		if let urlString = information["SUFeedURL"] as? String, let feedURL = URL(string: urlString.unquoted)  {
			let bundleArchitectures = supportedArchitectures(for: bundle)
			return adaptFeedURL(feedURL, bundleArchitectures: bundleArchitectures, hostArchitecture: hostArchitecture)
		} else { // Maybe the app is built using DevMate
			// Check for the DevMate framework
			let frameworksURL = URL(fileURLWithPath: bundle.bundlePath, isDirectory: true).appendingPathComponent("Contents").appendingPathComponent("Frameworks")
			
			let frameworks = try? FileManager.default.contentsOfDirectory(atPath: frameworksURL.path)
			if !(frameworks?.contains(where: { $0.contains("DevMateKit") }) ?? false) {
				return nil
			}
			
			// The app uses Devmate, so lets get the appcast from their servers
			guard var feedURL = URL(string: "https://updates.devmate.com") else {
				return nil
			}
			
			feedURL.appendPathComponent(identifier)
			feedURL.appendPathExtension("xml")
			
			return feedURL
		}
	}
	
	/// Rewrites architecture-specific directory segments in a Sparkle feed URL (such as Wireshark's `/x86-64/` path)
	/// when the host and bundle require a different target architecture.
	static func adaptFeedURL(_ url: URL, bundleArchitectures: Set<CPUArchitecture>, hostArchitecture: CPUArchitecture = Self.hostArchitecture) -> URL {
		guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			return url
		}
		
		let splitPath = components.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
		guard splitPath.count >= 2 else {
			return url
		}
		
		let targetArchitecture: CPUArchitecture
		switch hostArchitecture {
		case .arm64:
			// Prefer arm64 feeds unless the installed bundle is explicitly x86_64-only.
			targetArchitecture = (bundleArchitectures == [.x86_64]) ? .x86_64 : .arm64
		case .x86_64:
			targetArchitecture = .x86_64
		}
		
		var updatedSegments = splitPath
		var didChange = false
		
		// Only inspect directory path segments (excluding the trailing file name segment).
		for index in 0..<(updatedSegments.count - 1) {
			let segment = updatedSegments[index].lowercased()
			switch targetArchitecture {
			case .arm64:
				if segment == "x86-64" || segment == "x86_64" {
					updatedSegments[index] = "arm64"
					didChange = true
				}
			case .x86_64:
				if segment == "arm64" || segment == "aarch64" {
					updatedSegments[index] = "x86-64"
					didChange = true
				}
			}
		}
		
		guard didChange else { return url }
		components.path = updatedSegments.joined(separator: "/")
		return components.url ?? url
	}
	
	/// Infers the target CPU architecture from an appcast enclosure URL's filename and immediate parent directory.
	static func enclosureArchitecture(for url: URL) -> EnclosureArchitecture {
		let pathComponents = url.pathComponents.filter { $0 != "/" }
		guard !pathComponents.isEmpty else { return .unspecified }
		
		// Inspect the filename and immediate parent directory segment (if any) to avoid false matches on domain names.
		let relevantSegments = pathComponents.suffix(2).joined(separator: "/").lowercased()
		let tokens = relevantSegments
			.components(separatedBy: CharacterSet.alphanumerics.inverted)
			.filter { !$0.isEmpty }
		
		guard !tokens.isEmpty else { return .unspecified }
		
		let universalTokens: Set<String> = ["universal", "universal2", "fat"]
		let arm64Tokens: Set<String> = ["arm64", "arm64e", "aarch64", "arm", "applesilicon"]
		let x86_64Tokens: Set<String> = ["x86_64", "x64", "amd64", "intel"]
		
		var hasUniversal = false
		var hasArm64 = false
		var hasX86_64 = false
		
		for (index, token) in tokens.enumerated() {
			if universalTokens.contains(token) {
				hasUniversal = true
			}
			if arm64Tokens.contains(token) {
				hasArm64 = true
			}
			if x86_64Tokens.contains(token) {
				hasX86_64 = true
			}
			
			if index + 1 < tokens.count {
				let nextToken = tokens[index + 1]
				if token == "apple" && nextToken == "silicon" {
					hasArm64 = true
				} else if token == "x86" && nextToken == "64" {
					hasX86_64 = true
				}
			}
		}
		
		if hasUniversal || (hasArm64 && hasX86_64) {
			return .universal
		} else if hasArm64 {
			return .arm64
		} else if hasX86_64 {
			return .x86_64
		} else {
			return .unspecified
		}
	}
	
	/// Returns whether an enclosure's inferred architecture is compatible with the host Mac and installed app bundle.
	static func isArchitectureCompatible(
		enclosure: EnclosureArchitecture,
		bundleArchitectures: Set<CPUArchitecture>,
		hostArchitecture: CPUArchitecture = Self.hostArchitecture
	) -> Bool {
		switch enclosure {
		case .universal, .unspecified:
			return true
		case .arm64:
			return hostArchitecture == .arm64
		case .x86_64:
			switch hostArchitecture {
			case .x86_64:
				return true
			case .arm64:
				// Never replace a native Apple Silicon (or universal) app with an x86_64-only build.
				// Only allow x86_64 enclosures on arm64 if the currently installed app is strictly x86_64-only.
				return bundleArchitectures == [.x86_64]
			}
		}
	}
	
	/// Preference score when multiple compatible appcast items share the same version.
	static func architecturePriority(
		for enclosure: EnclosureArchitecture,
		hostArchitecture: CPUArchitecture = Self.hostArchitecture
	) -> Int {
		switch hostArchitecture {
		case .arm64:
			switch enclosure {
			case .arm64: return 4
			case .universal: return 3
			case .unspecified: return 2
			case .x86_64: return 1
			}
		case .x86_64:
			switch enclosure {
			case .x86_64: return 4
			case .universal: return 3
			case .unspecified: return 2
			case .arm64: return 0
			}
		}
	}
	
	/// Returns whether the given item is Sparkle's shared empty appcast item (used to signal "no valid update").
	/// The empty item has no version or URL, so it is detected by identity rather than by inspecting its properties.
	static func isEmptyItem(_ item: SUAppcastItem) -> Bool {
		return item === SUAppcastItem.empty()
	}
	
	/// Returns whether the given Sparkle appcast item is compatible with the installed bundle and host architecture.
	static func isAppcastItemCompatible(
		_ item: SUAppcastItem,
		for bundle: Bundle,
		hostArchitecture: CPUArchitecture = Self.hostArchitecture
	) -> Bool {
		let bundleArchitectures = supportedArchitectures(for: bundle)
		return isAppcastItemCompatible(item, bundleArchitectures: bundleArchitectures, hostArchitecture: hostArchitecture)
	}
	
	/// Returns whether the given Sparkle appcast item is compatible with the specified bundle architectures and host architecture.
	static func isAppcastItemCompatible(
		_ item: SUAppcastItem,
		bundleArchitectures: Set<CPUArchitecture>,
		hostArchitecture: CPUArchitecture = Self.hostArchitecture
	) -> Bool {
		guard !isEmptyItem(item) else { return false }
		guard item.arm64HardwareRequirementIsOK, item.maximumOperatingSystemVersionIsOK else {
			return false
		}
		if let fileURL = item.fileURL {
			let enclosureArch = enclosureArchitecture(for: fileURL)
			if !isArchitectureCompatible(enclosure: enclosureArch, bundleArchitectures: bundleArchitectures, hostArchitecture: hostArchitecture) {
				return false
			}
		}
		return true
	}
	
	/// Selects the best architecture-compatible update item from an appcast for the given app bundle.
	static func bestValidUpdate(
		in appcast: SUAppcast,
		for bundle: Bundle,
		hostArchitecture: CPUArchitecture = Self.hostArchitecture
	) -> SUAppcastItem? {
		let bundleArchitectures = supportedArchitectures(for: bundle)
		let candidates = appcast.items.filter { item in
			!item.isDeltaUpdate && isAppcastItemCompatible(item, bundleArchitectures: bundleArchitectures, hostArchitecture: hostArchitecture)
		}
		
		guard !candidates.isEmpty else {
			return SUAppcastItem.empty()
		}
		
		// Prefer items whose minimum macOS requirement is satisfied on the current system, matching Sparkle's driver behavior.
		let osCompatibleCandidates = candidates.filter { $0.minimumOperatingSystemVersionIsOK }
		let pool = osCompatibleCandidates.isEmpty ? candidates : osCompatibleCandidates
		
		var bestItem: SUAppcastItem?
		for candidate in pool {
			guard let currentBest = bestItem else {
				bestItem = candidate
				continue
			}
			
			let currentVersion = Version(versionNumber: currentBest.displayVersionString, buildNumber: currentBest.versionString)
			let candidateVersion = Version(versionNumber: candidate.displayVersionString, buildNumber: candidate.versionString)
			
			if candidateVersion > currentVersion {
				bestItem = candidate
			} else if candidateVersion == currentVersion {
				let currentArch = currentBest.fileURL.map { enclosureArchitecture(for: $0) } ?? .unspecified
				let candidateArch = candidate.fileURL.map { enclosureArchitecture(for: $0) } ?? .unspecified
				if architecturePriority(for: candidateArch, hostArchitecture: hostArchitecture) >
					architecturePriority(for: currentArch, hostArchitecture: hostArchitecture) {
					bestItem = candidate
				}
			}
		}
		
		return bestItem ?? SUAppcastItem.empty()
	}
	
}

fileprivate extension String {
	
	/// Returns the string with quotation marks trimmed.
	var unquoted: String {
		return NSString(string: self).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
	}
	
}
