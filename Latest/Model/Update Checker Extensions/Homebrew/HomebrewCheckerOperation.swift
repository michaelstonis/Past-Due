//
//  HomebrewCheckerOperation.swift
//  Latest
//
//  Created by Max Langer on 12.03.22.
//  Copyright © 2022 Max Langer. All rights reserved.
//

import Cocoa

/// The operation for checking for updates via Homebrew.
class HomebrewCheckerOperation: StatefulOperation, UpdateCheckerOperation, @unchecked Sendable {
	
	static var sourceType: App.Source {
		return .none
	}
	
	/// The bundle to be checked for updates.
	private let bundle: App.Bundle
	
	/// The update fetched during the checking operation.
	fileprivate var update: App.Update?
	
	private let repository: UpdateRepository?
	
	static func canPerformUpdateCheck(forAppAt url: URL) -> Bool {
		return true
	}
		
	required init(with bundle: App.Bundle, repository: UpdateRepository?, completionBlock: @escaping UpdateCheckerCompletionBlock) {
		self.bundle =  bundle
		self.repository = repository
		
		super.init()
		
		self.completionBlock = {
			if let update = self.update {
				completionBlock(.success(update))
			} else {
				completionBlock(.failure(self.error ?? LatestError.updateInfoUnavailable))
			}
		}
	}
	
	
	// MARK: - Operation

	override func execute() {
		// 1. Check if this bundle represents an installed Homebrew CLI formula in Cellar
		if let formulaToken = bundle.homebrewFormulaToken {
			let remoteVersion = HomebrewUpdateOperation.outdatedFormulaVersion(for: formulaToken) ?? bundle.version
			let meta = HomebrewUpdateOperation.formulaMetadata(for: bundle)
			let repoSlug = Self.extractGitHubRepoSlug(from: [meta.sourceURL, meta.homepage])
			
			Self.fetchGitHubChangelogHTML(
				repoSlug: repoSlug,
				installedVersion: bundle.version,
				remoteVersion: remoteVersion
			) { changelogHTML in
				let html = Self.formattedInfoCardHTML(
					name: self.bundle.name,
					token: formulaToken,
					kindLabel: "Homebrew Formula (CLI)",
					isManagedByHomebrew: true,
					installedVersion: self.bundle.version,
					remoteVersion: remoteVersion,
					upgradeCommand: "brew upgrade --formula \(formulaToken)",
					description: meta.description,
					homepage: meta.homepage,
					caveats: nil,
					githubRepoSlug: repoSlug,
					changelogHTML: changelogHTML
				)
				let action = App.Update.Action.builtIn { app in
					UpdateQueue.shared.addOperation(
						HomebrewUpdateOperation(
							bundleIdentifier: app.bundleIdentifier,
							appIdentifier: app.identifier,
							caskToken: formulaToken,
							packageKind: .formula
						)
					)
				}
				self.update = App.Update(
					app: self.bundle,
					remoteVersion: remoteVersion,
					minimumOSVersion: nil,
					source: .homebrew,
					date: nil,
					releaseNotes: .html(string: html),
					updateAction: action
				)
				self.finish()
			}
			return
		}
		
		// 2. Otherwise check Homebrew Cask catalog (and local Caskroom fallback for custom-tap casks)
		guard let repository else {
			self.finish()
			return
		}
		
		repository.updateEntry(for: bundle) { bundle, entry in
			let installedCaskToken = HomebrewUpdateOperation.installedCaskToken(forAppAt: bundle.fileURL)
			let token = entry?.token ?? installedCaskToken
			let remoteVersion = entry?.version ?? token.flatMap { HomebrewUpdateOperation.outdatedCaskVersion(for: $0) } ?? (installedCaskToken != nil ? bundle.version : nil)
			guard let remoteVersion else {
				self.finish()
				return
			}
			
			let isManaged = token.map { HomebrewUpdateOperation.canUpdate(caskToken: $0) } ?? false
			let action: App.Update.Action
			if let token, isManaged {
				action = .builtIn(block: { app in
					UpdateQueue.shared.addOperation(HomebrewUpdateOperation(bundleIdentifier: app.bundleIdentifier, appIdentifier: app.identifier, caskToken: token, packageKind: .cask))
				})
			} else {
				action = .external(label: bundle.name, block: { app in
					app.open()
				})
			}
			
			guard let token else {
				self.update = App.Update(
					app: bundle,
					remoteVersion: remoteVersion,
					minimumOSVersion: entry?.minimumOSVersion,
					source: .homebrew,
					date: nil,
					releaseNotes: nil,
					updateAction: action
				)
				self.finish()
				return
			}
			
			let repoSlug = Self.extractGitHubRepoSlug(from: [entry?.downloadURL, entry?.verifiedURL, entry?.homepage])
			Self.fetchGitHubChangelogHTML(
				repoSlug: repoSlug,
				installedVersion: bundle.version,
				remoteVersion: remoteVersion
			) { changelogHTML in
				let html = Self.formattedInfoCardHTML(
					name: bundle.name,
					token: token,
					kindLabel: isManaged ? "Homebrew Cask (Managed in Caskroom)" : "Homebrew Cask Catalog (External App)",
					isManagedByHomebrew: isManaged,
					installedVersion: bundle.version,
					remoteVersion: remoteVersion,
					upgradeCommand: isManaged ? "brew upgrade --cask --greedy \(token)" : "brew install --cask \(token)",
					description: entry?.description,
					homepage: entry?.homepage,
					caveats: entry?.caveats,
					githubRepoSlug: repoSlug,
					changelogHTML: changelogHTML
				)
				self.update = App.Update(
					app: bundle,
					remoteVersion: remoteVersion,
					minimumOSVersion: entry?.minimumOSVersion,
					source: .homebrew,
					date: nil,
					releaseNotes: .html(string: html),
					updateAction: action
				)
				self.finish()
			}
		}
	}
	
	/// Builds a formatted HTML info card for Homebrew Casks and Formulae displayed in the Release Notes pane.
	static func formattedInfoCardHTML(
		name: String,
		token: String,
		kindLabel: String,
		isManagedByHomebrew: Bool,
		installedVersion: Version? = nil,
		remoteVersion: Version? = nil,
		upgradeCommand: String,
		description: String?,
		homepage: String?,
		caveats: String?,
		githubRepoSlug: String? = nil,
		changelogHTML: String? = nil
	) -> String {
		var sections = [String]()
		sections.append("<h2>\(escapeHTML(name))</h2>")
		
		if let description, !description.isEmpty {
			sections.append("<p>\(escapeHTML(description))</p>")
		}
		
		// Version comparison & diff links when an update is available
		let curStr = installedVersion?.versionNumber ?? installedVersion?.buildNumber
		let newStr = remoteVersion?.versionNumber ?? remoteVersion?.buildNumber
		if let curStr, let newStr, curStr != newStr {
			sections.append("<h3>What's Changing (\(escapeHTML(curStr)) → \(escapeHTML(newStr)))</h3>")
			if let changelogHTML, !changelogHTML.isEmpty {
				sections.append(changelogHTML)
				if let githubRepoSlug, !changelogHTML.contains("/compare/") {
					let compareURL = "https://github.com/\(escapeHTML(githubRepoSlug))/compare/v\(escapeHTML(curStr))...v\(escapeHTML(newStr))"
					sections.append("<p><a href=\"\(compareURL)\">Compare full commit diff on GitHub (v\(escapeHTML(curStr))...v\(escapeHTML(newStr))) →</a></p>")
				}
			} else if let githubRepoSlug {
				let compareURL = "https://github.com/\(escapeHTML(githubRepoSlug))/compare/v\(escapeHTML(curStr))...v\(escapeHTML(newStr))"
				let releasesURL = "https://github.com/\(escapeHTML(githubRepoSlug))/releases"
				sections.append("<p>Update from version <b>\(escapeHTML(curStr))</b> to <b>\(escapeHTML(newStr))</b>. View the <a href=\"\(releasesURL)\">GitHub Releases</a> or <a href=\"\(compareURL)\">Compare v\(escapeHTML(curStr))...v\(escapeHTML(newStr))</a> for full commit diffs.</p>")
			} else {
				sections.append("<p>Updates <b>\(escapeHTML(name))</b> from version <b>\(escapeHTML(curStr))</b> to <b>\(escapeHTML(newStr))</b>.</p>")
			}
		} else if let changelogHTML, !changelogHTML.isEmpty {
			sections.append("<h3>Recent Releases</h3>")
			sections.append(changelogHTML)
		}
		
		sections.append("<h3>Homebrew Package Details</h3>")
		var details = [String]()
		details.append("<li><b>Token:</b> <code>\(escapeHTML(token))</code></li>")
		details.append("<li><b>Source:</b> \(escapeHTML(kindLabel))</li>")
		if let curStr, let newStr {
			if curStr != newStr {
				details.append("<li><b>Version Change:</b> <code>\(escapeHTML(curStr))</code> → <code>\(escapeHTML(newStr))</code></li>")
			} else {
				details.append("<li><b>Installed Version:</b> <code>\(escapeHTML(curStr))</code> (Up to date)</li>")
			}
		}
		if isManagedByHomebrew {
			details.append("<li><b>Update Command:</b> <code>\(escapeHTML(upgradeCommand))</code></li>")
		} else {
			details.append("<li><b>Note:</b> Installed outside Homebrew's Caskroom. Version information is provided by the Homebrew Cask catalog.</li>")
		}
		if let homepage, !homepage.isEmpty {
			let safeURL = escapeHTML(homepage)
			details.append("<li><b>Homepage:</b> <a href=\"\(safeURL)\">\(safeURL)</a></li>")
		}
		if let githubRepoSlug {
			let releasesURL = "https://github.com/\(escapeHTML(githubRepoSlug))/releases"
			details.append("<li><b>Changelog:</b> <a href=\"\(releasesURL)\">github.com/\(escapeHTML(githubRepoSlug))/releases</a></li>")
		}
		sections.append("<ul>\(details.joined())</ul>")
		
		if let caveats, !caveats.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			sections.append("<h3>Caveats</h3>")
			sections.append("<pre><code>\(escapeHTML(caveats.trimmingCharacters(in: .whitespacesAndNewlines)))</code></pre>")
		}
		
		return sections.joined(separator: "\n")
	}
	
	// MARK: - GitHub Changelog Extraction
	
	private static let githubCacheLock = NSLock()
	private static var githubReleasesCache = [String: [GitHubRelease]]()
	
	private struct GitHubRelease: Decodable {
		let tag_name: String
		let name: String?
		let body: String?
		let html_url: String?
		let prerelease: Bool?
		let draft: Bool?
	}
	
	/// Extracts `<owner>/<repo>` from candidate URL strings if any point to GitHub.
	static func extractGitHubRepoSlug(from candidates: [String?]) -> String? {
		for candidate in candidates.compactMap({ $0 }) {
			let lower = candidate.lowercased()
			guard let range = lower.range(of: "github.com/") else { continue }
			let suffix = candidate[range.upperBound...]
			let parts = suffix.split(separator: "/").map(String.init)
			guard parts.count >= 2 else { continue }
			let owner = parts[0]
			var repo = parts[1]
			if repo.hasSuffix(".git") {
				repo.removeLast(4)
			}
			guard !owner.isEmpty, !repo.isEmpty, owner != "orgs", owner != "sponsors" else { continue }
			return "\(owner)/\(repo)"
		}
		return nil
	}
	
	/// Fetches recent GitHub releases for `repoSlug` and formats release notes between `installedVersion` and `remoteVersion` into HTML.
	private static func fetchGitHubChangelogHTML(
		repoSlug: String?,
		installedVersion: Version,
		remoteVersion: Version,
		completion: @escaping (String?) -> Void
	) {
		guard let repoSlug else {
			completion(nil)
			return
		}
		// Only perform network fetch when an update is actually available (or if already cached)
		let hasUpdate = installedVersion < remoteVersion
		githubCacheLock.lock()
		let cached = githubReleasesCache[repoSlug]
		githubCacheLock.unlock()
		
		if let cached {
			completion(renderGitHubReleases(cached, repoSlug: repoSlug, installedVersion: installedVersion, remoteVersion: remoteVersion))
			return
		}
		guard hasUpdate, let url = URL(string: "https://api.github.com/repos/\(repoSlug)/releases?per_page=8") else {
			completion(nil)
			return
		}
		
		var request = URLRequest(url: url, timeoutInterval: 4.0)
		request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
		request.setValue("Past-Due", forHTTPHeaderField: "User-Agent")
		
		URLSession.shared.dataTask(with: request) { data, response, _ in
			guard let data,
				  let http = response as? HTTPURLResponse, http.statusCode == 200,
				  let releases = try? JSONDecoder().decode([GitHubRelease].self, from: data) else {
				completion(nil)
				return
			}
			githubCacheLock.lock()
			githubReleasesCache[repoSlug] = releases
			githubCacheLock.unlock()
			completion(renderGitHubReleases(releases, repoSlug: repoSlug, installedVersion: installedVersion, remoteVersion: remoteVersion))
		}.resume()
	}
	
	private static func renderGitHubReleases(
		_ releases: [GitHubRelease],
		repoSlug: String,
		installedVersion: Version,
		remoteVersion: Version
	) -> String? {
		let stableReleases = releases.filter { $0.draft != true && $0.prerelease != true }
		guard !stableReleases.isEmpty else { return nil }
		
		let relevant = stableReleases.filter { release in
			let v = VersionParser.parse(combinedVersionNumber: release.tag_name)
			if !v.isEmpty && installedVersion < remoteVersion {
				return v > installedVersion && v <= remoteVersion
			}
			return false
		}
		let chosen = relevant.isEmpty ? Array(stableReleases.prefix(2)) : Array(relevant.prefix(5))
		var blocks = [String]()
		
		for release in chosen {
			let title = (release.name?.isEmpty == false ? release.name! : release.tag_name)
			if let url = release.html_url {
				blocks.append("<h4><a href=\"\(escapeHTML(url))\">\(escapeHTML(title))</a></h4>")
			} else {
				blocks.append("<h4>\(escapeHTML(title))</h4>")
			}
			if let body = release.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
				blocks.append(markdownSummaryToHTML(body))
			}
		}
		
		if let curStr = installedVersion.versionNumber ?? installedVersion.buildNumber,
		   let newStr = remoteVersion.versionNumber ?? remoteVersion.buildNumber,
		   curStr != newStr {
			let compareURL = "https://github.com/\(escapeHTML(repoSlug))/compare/\(escapeHTML(chosen.last?.tag_name ?? "v\(curStr)"))...\(escapeHTML(chosen.first?.tag_name ?? "v\(newStr)"))"
			blocks.append("<p><a href=\"\(compareURL)\">Compare full commit diff on GitHub →</a></p>")
		}
		
		return blocks.isEmpty ? nil : blocks.joined(separator: "\n")
	}
	
	/// Converts GitHub Flavored Markdown release notes into clean HTML paragraphs and bullet lists.
	private static func markdownSummaryToHTML(_ markdown: String) -> String {
		var htmlLines = [String]()
		var inList = false
		let lines = markdown.components(separatedBy: .newlines).prefix(40)
		
		for rawLine in lines {
			let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
			if trimmed.isEmpty {
				if inList {
					htmlLines.append("</ul>")
					inList = false
				}
				continue
			}
			if trimmed.hasPrefix("#") {
				if inList {
					htmlLines.append("</ul>")
					inList = false
				}
				let headerText = trimmed.drop(while: { $0 == "#" || $0 == " " })
				htmlLines.append("<p><b>\(escapeHTML(String(headerText)))</b></p>")
			} else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
				if !inList {
					htmlLines.append("<ul>")
					inList = true
				}
				let itemText = String(trimmed.dropFirst(2))
				htmlLines.append("<li>\(formatInlineCode(escapeHTML(itemText)))</li>")
			} else {
				if inList {
					htmlLines.append("</ul>")
					inList = false
				}
				htmlLines.append("<p>\(formatInlineCode(escapeHTML(trimmed)))</p>")
			}
		}
		if inList {
			htmlLines.append("</ul>")
		}
		return htmlLines.joined(separator: "\n")
	}
	
	private static func formatInlineCode(_ escapedHTML: String) -> String {
		let parts = escapedHTML.components(separatedBy: "`")
		guard parts.count > 1 else { return escapedHTML }
		var result = ""
		for (index, part) in parts.enumerated() {
			if index % 2 == 1 {
				result += "<code>\(part)</code>"
			} else {
				result += part
			}
		}
		return result
	}
	
	private static func escapeHTML(_ text: String) -> String {
		text
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
	}
	
}
