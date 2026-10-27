//
//  AppDelegate.swift
//  Latest
//
//  Created by Max Langer on 15.02.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        BackgroundUpdateScheduler.shared.showMainWindowHandler = { [weak self] in
            self?.showMainWindow()
        }
        BackgroundUpdateScheduler.shared.start()
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
		// Keep running in the background when scheduled automatic update checks are enabled
		return !BackgroundCheckSettings.shared.automaticChecksEnabled
	}
	
	private func showMainWindow() {
		if let window = NSApp.windows.first(where: { $0.windowController is MainWindowController }) {
			window.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
		}
	}
    
}

