//
//  main.swift
//  Latest
//
//  Copyright © 2026 Max Langer. All rights reserved.
//

import AppKit

if CommandLineInterface.shouldRunCLI(arguments: CommandLine.arguments) {
	exit(CommandLineInterface.run(arguments: CommandLine.arguments))
} else {
	_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}
