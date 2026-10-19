//
//  DisplayLink.swift
//
//  Created by Max Langer on 23.05.17.
//  Copyright © 2017 Max Langer. All rights reserved.
//

import AppKit
import QuartzCore

/// Convenience for driving frame-synchronized animations on macOS 15+ using CADisplayLink,
/// with a safe Timer fallback when no active display is available (e.g., when displays are asleep).
class DisplayLink: NSObject {

	/// Weak target proxy to prevent CADisplayLink / Timer from retaining DisplayLink.
	private final class WeakTarget: NSObject {
		weak var owner: DisplayLink?
		init(owner: DisplayLink) {
			self.owner = owner
		}
		@objc func tick() {
			owner?.displayTick()
		}
	}

	/// The amount of time the display link should be running. If set to `nil`, the display link runs indefinitely.
	private(set) var duration: Double?

	/// An optional completion handler called after the display link stopped animating.
	var completionHandler: (() -> Void)?

	/// The current animation progress. Only useful if a duration has been set.
	private(set) var progress: Double = 0

	private var displayLink: CADisplayLink?
	private var fallbackTimer: Timer?
	private var lastTimestamp: CFTimeInterval?

	/// Frames used to calculate the animation progress
	private var _currentFrame: Double = 0
	private var _frames: Double = 0

	/// The callback called for each animation step.
	private(set) var callback: ((_ progress: Double) -> Void)!

	// MARK: - Initialization

	/// Initializes the display link with the given duration and callback.
	init(duration: Double?, callback: @escaping ((_ progress: Double) -> Void)) {
		super.init()

		self.duration = duration
		self.callback = callback
	}

	deinit {
		displayLink?.invalidate()
		fallbackTimer?.invalidate()
	}

	// MARK: - Animation

	@objc private func displayTick() {
		let dt: Double
		if let displayLink {
			let duration = displayLink.targetTimestamp - displayLink.timestamp
			dt = duration > 0 ? duration : (1.0 / 60.0)
		} else {
			let now = CACurrentMediaTime()
			if let last = lastTimestamp {
				dt = max(1.0 / 240.0, min(0.1, now - last))
			} else {
				dt = 1.0 / 60.0
			}
			lastTimestamp = now
		}

		if let duration = self.duration {
			self._frames = duration / dt
		} else {
			self._frames = 1
		}

		// Make 60 FPS the default rate and adjust progress increases based on the actual refresh period.
		self._currentFrame += dt / (1.0 / 60.0)

		self.progress = self._currentFrame / self._frames
		if self.duration != nil, self.progress >= 1 {
			self.completionHandler?()
			self.stop()
		}

		self.callback(self.progress)
	}

	// MARK: - Actions

	/// Starts the display link.
	func start() {
		self._currentFrame = 0
		self.lastTimestamp = CACurrentMediaTime()

		let runOnMain = { [weak self] in
			guard let self else { return }
			self.displayLink?.invalidate()
			self.fallbackTimer?.invalidate()

			let proxy = WeakTarget(owner: self)
			if let screen = NSScreen.main ?? NSScreen.screens.first {
				let link = screen.displayLink(target: proxy, selector: #selector(WeakTarget.tick))
				link.add(to: .main, forMode: .common)
				link.isPaused = false
				self.displayLink = link
			} else {
				let timer = Timer(timeInterval: 1.0 / 60.0, target: proxy, selector: #selector(WeakTarget.tick), userInfo: nil, repeats: true)
				RunLoop.main.add(timer, forMode: .common)
				self.fallbackTimer = timer
			}
		}

		if Thread.isMainThread {
			runOnMain()
		} else {
			DispatchQueue.main.async(execute: runOnMain)
		}
	}

	/// Stops the display link.
	func stop() {
		let stopOnMain = { [weak self] in
			guard let self else { return }
			self.displayLink?.isPaused = true
			self.displayLink?.invalidate()
			self.displayLink = nil
			self.fallbackTimer?.invalidate()
			self.fallbackTimer = nil
		}

		if Thread.isMainThread {
			stopOnMain()
		} else {
			DispatchQueue.main.async(execute: stopOnMain)
		}
	}

	/// Whether the display link is currently running.
	var isRunning: Bool {
		if let displayLink {
			return !displayLink.isPaused
		}
		return fallbackTimer?.isValid ?? false
	}

}
