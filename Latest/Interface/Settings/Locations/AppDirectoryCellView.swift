//
//  AppDirectoryCellView.swift
//  Latest
//
//  Created by Max Langer on 29.02.24.
//  Copyright © 2024 Max Langer. All rights reserved.
//

import Cocoa

/// View that holds a single location checked for updates.
class AppDirectoryCellView: NSTableCellView {
	
	/// The label holding the path of the directory.
	@IBOutlet private weak var titleLabel: NSTextField!
	
	/// The image view displaying the directories icon.
	@IBOutlet private weak var iconImageView: NSImageView!
	
	/// The label holding the app count for this directory.
	@IBOutlet private weak var appCountLabel: NSTextField!
	
	/// The activity indicator shown while the apps are being counted.
	@IBOutlet private weak var activityIndicator: NSProgressIndicator!
	
	private var enabledCheckbox: NSButton?
	private var toggleHandler: ((Bool) -> Void)?
	
	/// The URL to be displayed by the cell.
	var url: URL? {
		didSet {
			guard url != oldValue else {
				updateAppearance()
				return
			}
			
			isReachable = (try? url?.checkResourceIsReachable()) == true
			setUpView()
		}
	}
	
	var isDirectoryEnabled: Bool = true {
		didSet {
			enabledCheckbox?.state = isDirectoryEnabled ? .on : .off
			updateAppearance()
		}
	}
	
	var isReachable: Bool = false
	
	override func awakeFromNib() {
		super.awakeFromNib()
		setupCheckboxIfNeeded()
	}
	
	func configure(url: URL, isEnabled: Bool, toggleHandler: @escaping (Bool) -> Void) {
		setupCheckboxIfNeeded()
		self.toggleHandler = toggleHandler
		self.isDirectoryEnabled = isEnabled
		self.url = url
	}
	
	private func setupCheckboxIfNeeded() {
		guard enabledCheckbox == nil,
			  let stackView = subviews.compactMap({ $0 as? NSStackView }).first else {
			return
		}
		let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
		checkbox.setContentHuggingPriority(.required, for: .horizontal)
		stackView.insertArrangedSubview(checkbox, at: 0)
		self.enabledCheckbox = checkbox
	}
	
	@objc private func toggleEnabled(_ sender: NSButton) {
		let enabled = (sender.state == .on)
		isDirectoryEnabled = enabled
		toggleHandler?(enabled)
	}
	
	private func updateAppearance() {
		titleLabel.textColor = tintColor
		iconImageView.alphaValue = isDirectoryEnabled ? 1.0 : 0.45
		appCountLabel.alphaValue = isDirectoryEnabled ? 1.0 : 0.45
	}
	
	private func setUpView() {
		guard let url else {
			titleLabel.stringValue = ""
			iconImageView.image = nil
			appCountLabel.isHidden = true
			return
		}
		
		// Title
		titleLabel.stringValue = url.relativePath
		updateAppearance()
		
		// Image
		iconImageView.image = icon
		
		// App Count
		activityIndicator.startAnimation(nil)
		appCountLabel.isHidden = true
		DispatchQueue.global().async {
			let count = BundleCollector.collectBundles(at: url).count
			DispatchQueue.main.async {
				self.appCountLabel.isHidden = false
				self.activityIndicator.stopAnimation(nil)
				self.appCountLabel.stringValue = NumberFormatter.localizedString(from: NSNumber(value: count), number: .none)
			}
		}
	}
	
	private var tintColor: NSColor {
		(isReachable && isDirectoryEnabled) ? .labelColor : .secondaryLabelColor
	}
	
	private var icon: NSImage {
		if isReachable {
			guard let url else { return NSImage() }
			return NSWorkspace.shared.icon(forFile: url.relativePath)
		}
		
		return NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "")!
	}
}
