// LunaDsiplayLink.swift
//
// macOS-only: CVDisplayLink wrapper that is Swift 6 strict-concurrency friendly.
//
// Key constraints:
// - CVDisplayLink callback runs on a background thread.
// - Must not touch AppKit there.
// - Swift 6 complains if we capture task-isolated values (`self`, `context`) into a
//   closure that is treated as main-actor isolated.
// - We also cannot use `self` before all stored properties are initialized.
//
// Approach used here:
// - Create the CVDisplayLink first and store it.
// - Install callback with context = unmanaged pointer to self (standard pattern).
// - In callback thread: coalesce and schedule work onto the main runloop via
//   CFRunLoopPerformBlock.
// - Inside the runloop block: reconstitute `self` from the raw pointer *inside*
//   the block (so we do not capture `self` across the hop).
//
// Note: We do NOT store any "selfToken" property to avoid init-order issues.

#if os(macOS)
import Foundation
import CoreVideo
import CoreFoundation

public final class LunaDisplayLink {

    // MARK: - Public API

    /// Called once per display refresh tick on the MAIN THREAD.
    public var onFrame: (() -> Void)?

    public func start() {
        lock.lock()
        defer { lock.unlock() }

        guard let displayLink else { return }
        guard !isRunning else { return }

        pending = false

        let rc = CVDisplayLinkStart(displayLink)
        if rc == kCVReturnSuccess {
            isRunning = true
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard let displayLink else { return }
        guard isRunning else { return }

        CVDisplayLinkStop(displayLink)
        isRunning = false
        pending = false
    }

    // MARK: - Lifecycle

    public init() {
        var dl: CVDisplayLink?
        let rc = CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        guard rc == kCVReturnSuccess, let created = dl else {
            self.displayLink = nil
            return
        }

        self.displayLink = created

        // Safe now: all stored properties have initial values (displayLink is set).
        // Install callback with context = unretained self.
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkSetOutputCallback(created, LunaDisplayLink.outputCallback, context)
    }

    deinit {
        stop()
        if let dl = displayLink {
            // Ensure callback cannot fire into freed memory.
            CVDisplayLinkSetOutputCallback(dl, nil, nil)
        }
    }

    // MARK: - Private

    private let lock = NSLock()
    private let displayLink: CVDisplayLink?

    private var isRunning: Bool = false
    private var pending: Bool = false

    private static let outputCallback: CVDisplayLinkOutputCallback = { _, _, _, _, _, context in
        guard let context else { return kCVReturnSuccess }

        // We are on a background thread. We must not touch AppKit.
        // Reconstitute `self` on this thread:
        let obj = Unmanaged<LunaDisplayLink>.fromOpaque(context).takeUnretainedValue()
        obj.tickFromCallbackThread(context: context)

        return kCVReturnSuccess
    }

    /// Called on the CVDisplayLink callback thread.
    ///
    /// We coalesce scheduling and then schedule a main-runloop block via
    /// CFRunLoopPerformBlock. The block reconstitutes `self` from `context`
    /// inside the block (no capturing `self` across thread hop).
    private func tickFromCallbackThread(context: UnsafeMutableRawPointer) {

        lock.lock()
        if pending {
            lock.unlock()
            return
        }
        pending = true
        lock.unlock()

        // Convert raw pointer to an Int value so the closure captures a Sendable value.
        let token = Int(bitPattern: context)

        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {

            guard let ptr = UnsafeRawPointer(bitPattern: token) else { return }
            let obj = Unmanaged<LunaDisplayLink>.fromOpaque(ptr).takeUnretainedValue()

            obj.lock.lock()
            obj.pending = false
            let frame = obj.onFrame
            obj.lock.unlock()

            frame?()
        }

        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}
#endif
