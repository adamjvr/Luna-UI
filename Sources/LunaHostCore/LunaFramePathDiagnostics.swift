// SPDX-License-Identifier: MPL-2.0
//
// LunaFramePathDiagnostics.swift
//
// C2.5D: frame-path classification and cache-path instrumentation.
//
// These values live at the host/runtime boundary so applications and demo
// harnesses can report how a frame was produced without making synchronous
// LunaUI widgets own timers, threads, or retained rendering state.

import Foundation

/// High-level cause of one presented frame.
public enum LunaFrameInvalidationClass: String, Hashable, Sendable, CustomStringConvertible {
    case none
    case initial
    case animationOnly
    case inputDriven
    case resizeDriven
    case stateDriven
    case mixed

    public init(invalidations: LunaFrameInvalidationSet) {
        let reasons = invalidations.reasons

        guard !reasons.isEmpty else {
            self = .none
            return
        }

        if reasons == Set([LunaInvalidationReason.initial]) {
            self = .initial
            return
        }

        if reasons == Set([LunaInvalidationReason.animation]) {
            self = .animationOnly
            return
        }

        if reasons == Set([LunaInvalidationReason.windowResized]) {
            self = .resizeDriven
            return
        }

        let inputReasons: Set<LunaInvalidationReason> = [
            .input,
            .textInput,
            .documentChanged,
            .selectionChanged,
            .scrollChanged,
            .commandExecuted,
            .caretBlink,
        ]
        if reasons.isSubset(of: inputReasons) {
            self = .inputDriven
            return
        }

        let stateReasons: Set<LunaInvalidationReason> = [
            .overlayChanged,
            .themeChanged,
            .workspaceChanged,
            .asyncResult,
            .accessibilityChanged,
        ]
        if reasons.isSubset(of: stateReasons) {
            self = .stateDriven
            return
        }

        self = .mixed
    }

    public var description: String { rawValue }
}

/// Rendering route used to produce one frame.
public enum LunaFrameRenderPath: String, Hashable, Sendable, CustomStringConvertible {
    /// The scene rebuilt its normal complete frame.
    case fullScene

    /// The scene restored a complete static cached frame, then drew dynamics.
    case cachedAnimation

    /// The scene restored and redrew only bounded damaged regions.
    case partialDamage

    /// The scene did not provide a report.
    case unknown

    public var description: String { rawValue }
}

/// Why a cache-backed path was not used.
public enum LunaFrameCacheMissReason: Hashable, Sendable, CustomStringConvertible {
    case notApplicable
    case cacheAbsent
    case sizeMismatch
    case transientOverlayActive
    case nonAnimationInvalidation
    case cacheRestoreFailed
    case explicit(String)

    public var description: String {
        switch self {
        case .notApplicable: return "notApplicable"
        case .cacheAbsent: return "cacheAbsent"
        case .sizeMismatch: return "sizeMismatch"
        case .transientOverlayActive: return "transientOverlayActive"
        case .nonAnimationInvalidation: return "nonAnimationInvalidation"
        case .cacheRestoreFailed: return "cacheRestoreFailed"
        case .explicit(let value): return "explicit(\(value))"
        }
    }
}

/// Fixed-field counters keep `LunaFrameTimingStats` synthesizably `Hashable`
/// while still providing enum-addressed access.
public struct LunaFrameRenderPathCounters: Hashable, Sendable {
    public private(set) var fullScene: UInt64 = 0
    public private(set) var cachedAnimation: UInt64 = 0
    public private(set) var partialDamage: UInt64 = 0
    public private(set) var unknown: UInt64 = 0

    public init() {}

    public mutating func record(_ path: LunaFrameRenderPath) {
        switch path {
        case .fullScene: fullScene &+= 1
        case .cachedAnimation: cachedAnimation &+= 1
        case .partialDamage: partialDamage &+= 1
        case .unknown: unknown &+= 1
        }
    }

    public func count(for path: LunaFrameRenderPath) -> UInt64 {
        switch path {
        case .fullScene: return fullScene
        case .cachedAnimation: return cachedAnimation
        case .partialDamage: return partialDamage
        case .unknown: return unknown
        }
    }
}

/// Fixed-field cache-miss counters. Explicit string reasons are aggregated.
public struct LunaFrameCacheMissCounters: Hashable, Sendable {
    public private(set) var notApplicable: UInt64 = 0
    public private(set) var cacheAbsent: UInt64 = 0
    public private(set) var sizeMismatch: UInt64 = 0
    public private(set) var transientOverlayActive: UInt64 = 0
    public private(set) var nonAnimationInvalidation: UInt64 = 0
    public private(set) var cacheRestoreFailed: UInt64 = 0
    public private(set) var explicit: UInt64 = 0

    public init() {}

    public mutating func record(_ reason: LunaFrameCacheMissReason) {
        switch reason {
        case .notApplicable: notApplicable &+= 1
        case .cacheAbsent: cacheAbsent &+= 1
        case .sizeMismatch: sizeMismatch &+= 1
        case .transientOverlayActive: transientOverlayActive &+= 1
        case .nonAnimationInvalidation: nonAnimationInvalidation &+= 1
        case .cacheRestoreFailed: cacheRestoreFailed &+= 1
        case .explicit: explicit &+= 1
        }
    }

    public func count(for reason: LunaFrameCacheMissReason) -> UInt64 {
        switch reason {
        case .notApplicable: return notApplicable
        case .cacheAbsent: return cacheAbsent
        case .sizeMismatch: return sizeMismatch
        case .transientOverlayActive: return transientOverlayActive
        case .nonAnimationInvalidation: return nonAnimationInvalidation
        case .cacheRestoreFailed: return cacheRestoreFailed
        case .explicit: return explicit
        }
    }

    public var eligibleMissCount: UInt64 {
        cacheAbsent
            &+ sizeMismatch
            &+ transientOverlayActive
            &+ nonAnimationInvalidation
            &+ cacheRestoreFailed
            &+ explicit
    }
}

/// Stage timings and classification supplied by a scene after rendering.
public struct LunaFrameRenderReport: Hashable, Sendable {
    public var path: LunaFrameRenderPath
    public var invalidationClass: LunaFrameInvalidationClass
    public var cacheMissReason: LunaFrameCacheMissReason?
    public var layoutNanoseconds: UInt64
    public var cacheRestoreNanoseconds: UInt64
    public var staticSceneNanoseconds: UInt64
    public var dynamicSceneNanoseconds: UInt64
    public var overlayNanoseconds: UInt64

    /// Number of bounded rectangles restored or redrawn by a partial frame.
    public var damagedRegionCount: Int

    /// Actual clipped pixels restored from backing storage.
    public var damagedPixelCount: Int

    public init(
        path: LunaFrameRenderPath,
        invalidationClass: LunaFrameInvalidationClass,
        cacheMissReason: LunaFrameCacheMissReason? = nil,
        layoutNanoseconds: UInt64 = 0,
        cacheRestoreNanoseconds: UInt64 = 0,
        staticSceneNanoseconds: UInt64 = 0,
        dynamicSceneNanoseconds: UInt64 = 0,
        overlayNanoseconds: UInt64 = 0,
        damagedRegionCount: Int = 0,
        damagedPixelCount: Int = 0
    ) {
        self.path = path
        self.invalidationClass = invalidationClass
        self.cacheMissReason = cacheMissReason
        self.layoutNanoseconds = layoutNanoseconds
        self.cacheRestoreNanoseconds = cacheRestoreNanoseconds
        self.staticSceneNanoseconds = staticSceneNanoseconds
        self.dynamicSceneNanoseconds = dynamicSceneNanoseconds
        self.overlayNanoseconds = overlayNanoseconds
        self.damagedRegionCount = max(0, damagedRegionCount)
        self.damagedPixelCount = max(0, damagedPixelCount)
    }

    public var measuredNanoseconds: UInt64 {
        layoutNanoseconds
            &+ cacheRestoreNanoseconds
            &+ staticSceneNanoseconds
            &+ dynamicSceneNanoseconds
            &+ overlayNanoseconds
    }

    public var measuredMilliseconds: Double {
        Double(measuredNanoseconds) / 1_000_000.0
    }

    public var usedStaticAnimationCache: Bool {
        path == .cachedAnimation || path == .partialDamage
    }

    public var wasCacheEligible: Bool {
        if usedStaticAnimationCache { return true }
        guard let cacheMissReason else { return false }
        return cacheMissReason != .notApplicable
    }

    public var statusText: String {
        var fields = [
            "path \(path.description)",
            "cause \(invalidationClass.description)",
            String(format: "scene %.2f ms", measuredMilliseconds),
        ]
        if damagedRegionCount > 0 {
            fields.append("damage \(damagedRegionCount)r/\(damagedPixelCount)px")
        }
        if let cacheMissReason {
            fields.append("miss \(cacheMissReason.description)")
        }
        return fields.joined(separator: " | ")
    }
}
