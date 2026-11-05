//
//  IconCache.swift
//  Latest
//
//  Created by Max Langer on 12.08.18.
//  Copyright © 2018 Max Langer. All rights reserved.
//

import AppKit

/// A cache for app icons.
class IconCache {
    
	/// The shared cache object.
    static var shared = IconCache()
    
	/// Initializes the cache.
    private init() {
        self.cache = NSCache()
    }

	/// The object storing app images.
	private var cache: NSCache<App, NSImage>
	
	/// Provides the icon for the given app through the given completion handler.
    func icon(for app: App, with completion: @escaping (NSImage) -> Void) {
        if let icon = self.cache.object(forKey: app) {
            completion(icon)
			return
        }
        
        DispatchQueue.main.async {
            let icon: NSImage
            if app.bundle.isHomebrewFormula {
                icon = Self.homebrewFormulaIcon()
            } else {
                icon = NSWorkspace.shared.icon(forFile: app.fileURL.path)
            }
            self.cache.setObject(icon, forKey: app)

            completion(icon)
        }
    }
    
    /// Returns the native macOS Terminal application icon for Homebrew CLI formulae so it blends naturally with macOS app icons.
    private static func homebrewFormulaIcon() -> NSImage {
        let terminalPath = "/System/Applications/Utilities/Terminal.app"
        if FileManager.default.fileExists(atPath: terminalPath) {
            return NSWorkspace.shared.icon(forFile: terminalPath)
        }
        return NSWorkspace.shared.icon(for: .unixExecutable)
    }
    
}
