// SPDX-License-Identifier: MPL-2.0
//
// LunaClipboardService.swift
//
// Platform-neutral plain-text clipboard boundary. Applications own the meaning
// of Copy, Cut, and Paste; Luna hosts only expose safe access to the native
// clipboard and deterministic in-memory implementations for tests.

import Foundation

public enum LunaClipboardError: Error, LocalizedError, Sendable {
    case unavailable
    case readFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The system clipboard is unavailable"
        case .readFailed(let detail):
            return "Could not read the system clipboard: \(detail)"
        case .writeFailed(let detail):
            return "Could not write the system clipboard: \(detail)"
        }
    }
}

public protocol LunaClipboardService: Sendable {
    /// Whether the concrete host can attempt native clipboard operations.
    /// This is intentionally capability-only; applications should still handle
    /// an empty clipboard and runtime read/write failures.
    var isAvailable: Bool { get }

    /// Returns nil when the clipboard contains no plain text.
    func readText() throws -> String?

    /// Replaces the native plain-text clipboard contents.
    func writeText(_ text: String) throws
}

public struct LunaUnavailableClipboardService: LunaClipboardService {
    public init() {}
    public var isAvailable: Bool { false }

    public func readText() throws -> String? {
        throw LunaClipboardError.unavailable
    }

    public func writeText(_ text: String) throws {
        throw LunaClipboardError.unavailable
    }
}

/// Thread-safe deterministic clipboard used by unit tests and headless hosts.
public final class LunaInMemoryClipboardService: LunaClipboardService, @unchecked Sendable {
    private let lock = NSLock()
    private var storedText: String?
    private var nextReadError: Error?
    private var nextWriteError: Error?

    public init(text: String? = nil) {
        self.storedText = text
    }

    public var isAvailable: Bool { true }

    public func readText() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let error = nextReadError {
            nextReadError = nil
            throw error
        }
        return storedText
    }

    public func writeText(_ text: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if let error = nextWriteError {
            nextWriteError = nil
            throw error
        }
        storedText = text
    }

    /// Configure one deterministic failure without making later calls fail.
    public func failNextRead(with error: Error = LunaClipboardError.readFailed("scripted failure")) {
        lock.lock()
        nextReadError = error
        lock.unlock()
    }

    /// Configure one deterministic failure without making later calls fail.
    public func failNextWrite(with error: Error = LunaClipboardError.writeFailed("scripted failure")) {
        lock.lock()
        nextWriteError = error
        lock.unlock()
    }
}
