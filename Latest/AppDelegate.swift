//
//  AppDelegate.swift
//  Latest
//
//  Created by Max Langer on 15.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {

	@IBOutlet weak var updaterController: SPUStandardUpdaterController?

	/// Presents Past Due's own standard Sparkle update dialog separately so Sparkle can handle downloading, installing, and relaunching the app.
	static func presentSelfUpdateDialog() {
		DispatchQueue.main.async {
			NSApp.activate(ignoringOtherApps: true)
			if let delegate = NSApp.delegate as? AppDelegate,
			   let controller = delegate.updaterController {
				controller.checkForUpdates(nil)
				return
			}
			if let appMenu = NSApp.mainMenu?.items.first?.submenu,
			   let checkItem = appMenu.items.first(where: { $0.action == #selector(SPUStandardUpdaterController.checkForUpdates(_:)) }),
			   let target = checkItem.target as? SPUStandardUpdaterController {
				target.checkForUpdates(checkItem)
				return
			}
			NSApp.sendAction(#selector(SPUStandardUpdaterController.checkForUpdates(_:)), to: nil, from: nil)
		}
	}

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        BackgroundUpdateScheduler.shared.showMainWindowHandler = { [weak self] in
            self?.showMainWindow()
        }
        BackgroundUpdateScheduler.shared.start()
        
        MenuBarController.shared.showMainWindowHandler = { [weak self] in
            self?.showMainWindow()
        }
        MenuBarController.shared.start()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
	
	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		if !flag {
			showMainWindow()
		}
		return true
	}
	
	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		// Keep running in the background when scheduled automatic update checks or the menu bar extra are enabled
		let settings = BackgroundCheckSettings.shared
		return !settings.automaticChecksEnabled && !settings.showMenuBarExtra
	}
	
	private func showMainWindow() {
		if let window = NSApp.windows.first(where: { $0.windowController is MainWindowController }) {
			window.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
		}
	}
    
}

