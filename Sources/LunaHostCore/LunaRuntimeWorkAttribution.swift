// SPDX-License-Identifier: MPL-2.0
//
// LunaRuntimeWorkAttribution.swift
//
// C2.5G: measured end-to-end host/runtime work attribution.

import Foundation

/// Capabilities reported by the SDL renderer that was actually created.
///
/// `vsyncWasRequested` describes policy. `hasPresentVSync` describes the
/// renderer flags SDL returned. They are intentionally separate: asking for
/// VSync does not prove that the selected renderer provides it.
public struct LunaSDLRendererCapabilities: Codable, Hashable, Sendable {
    public var rendererName: String
    public var querySucceeded: Bool
    public var requestedFlags: UInt32
    public var actualFlags: UInt32
    public var isSoftware: Bool
    public var isAccelerated: Bool
    public var supportsTargetTextures: Bool
    public var vsyncWasRequested: Bool
    public var hasPresentVSync: Bool
    public var maximumTextureWidth: Int
    public var maximumTextureHeight: Int

    public init(
        rendererName: String = "unknown",
        querySucceeded: Bool = false,
        requestedFlags: UInt32 = 0,
        actualFlags: UInt32 = 0,
        isSoftware: Bool = false,
        isAccelerated: Bool = false,
        supportsTargetTextures: Bool = false,
        vsyncWasRequested: Bool = false,
        hasPresentVSync: Bool = false,
        maximumTextureWidth: Int = 0,
        maximumTextureHeight: Int = 0
    ) {
        self.rendererName = rendererName
        self.querySucceeded = querySucceeded
        self.requestedFlags = requestedFlags
        self.actualFlags = actualFlags
        self.isSoftware = isSoftware
        self.isAccelerated = isAccelerated
        self.supportsTargetTextures = supportsTargetTextures
        self.vsyncWasRequested = vsyncWasRequested
        self.hasPresentVSync = hasPresentVSync
        self.maximumTextureWidth = max(0, maximumTextureWidth)
        self.maximumTextureHeight = max(0, maximumTextureHeight)
    }
}

/// Serializable process-lifetime attribution counters.
public struct LunaRuntimeWorkAttributionSnapshot: Codable, Hashable, Sendable {
    public var schemaVersion: Int = 1
    public var hostLoopIterations: UInt64 = 0
    public var inputPollingPasses: UInt64 = 0
    public var rawNativeEventCount: UInt64 = 0
    public var translatedSemanticEventCount: UInt64 = 0
    public var nativeBacklogIterations: UInt64 = 0
    public var semanticDispatchSlices: UInt64 = 0
    public var semanticEventsDispatched: UInt64 = 0
    public var maximumDeferredSemanticEvents: UInt64 = 0
    public var frameRequestCount: UInt64 = 0
    public var invalidationDrivenFrameRequests: UInt64 = 0
    public var continuousFrameRequests: UInt64 = 0
    public var renderCount: UInt64 = 0
    public var presentCount: UInt64 = 0
    public var fullSceneFrameCount: UInt64 = 0
    public var partialDamageFrameCount: UInt64 = 0
    public var cachedAnimationFrameCount: UInt64 = 0
    public var unattributedFrameCount: UInt64 = 0
    public var totalRenderNanoseconds: UInt64 = 0
    public var totalPresentNanoseconds: UInt64 = 0
    public var idleSleepCount: UInt64 = 0
    public var idleSleepMilliseconds: UInt64 = 0
    public var softwarePacingSleepCount: UInt64 = 0
    public var softwarePacingSleepMilliseconds: UInt64 = 0
    public var rendererCapabilities: LunaSDLRendererCapabilities?

    public init() {}
}

/// Thread-safe recorder used by the synchronous host loop.
///
/// The runtime remains single-lane; the lock only makes snapshot reads and
/// process-exit flushing safe for tests and diagnostics. Set
/// `LUNA_RUNTIME_TRACE_PATH=/path/to/luna-runtime.json` to emit one atomic JSON
/// file when the application exits.
public final class LunaRuntimeWorkAttributionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = LunaRuntimeWorkAttributionSnapshot()
    public let traceURL: URL?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let path = environment["LUNA_RUNTIME_TRACE_PATH"], !path.isEmpty {
            self.traceURL = URL(fileURLWithPath: path)
        } else {
            self.traceURL = nil
        }
    }

    public func recordRendererCapabilities(_ capabilities: LunaSDLRendererCapabilities) {
        lock.withLock { storage.rendererCapabilities = capabilities }
    }

    public func recordHostLoopIteration() {
        lock.withLock { storage.hostLoopIterations &+= 1 }
    }

    public func recordPollingPass(
        rawEventCount: Int,
        translatedEventCount: Int,
        mayHavePendingEvents: Bool
    ) {
        lock.withLock {
            storage.inputPollingPasses &+= 1
            storage.rawNativeEventCount &+= UInt64(max(0, rawEventCount))
            storage.translatedSemanticEventCount &+= UInt64(max(0, translatedEventCount))
            if mayHavePendingEvents { storage.nativeBacklogIterations &+= 1 }
        }
    }

    public func recordDispatchSlice(_ stats: LunaInputDispatchStats) {
        lock.withLock {
            storage.semanticDispatchSlices &+= 1
            storage.semanticEventsDispatched &+= UInt64(stats.processedEventCount)
            storage.maximumDeferredSemanticEvents = max(
                storage.maximumDeferredSemanticEvents,
                UInt64(stats.remainingEventCount)
            )
        }
    }

    public func recordFrameRequest(
        hasInvalidations: Bool,
        wantsContinuousFrames: Bool
    ) {
        lock.withLock {
            storage.frameRequestCount &+= 1
            if hasInvalidations { storage.invalidationDrivenFrameRequests &+= 1 }
            if wantsContinuousFrames { storage.continuousFrameRequests &+= 1 }
        }
    }

    public func recordFrame(
        renderNanoseconds: UInt64,
        presentNanoseconds: UInt64,
        renderReport: LunaFrameRenderReport?
    ) {
        lock.withLock {
            storage.renderCount &+= 1
            storage.presentCount &+= 1
            storage.totalRenderNanoseconds &+= renderNanoseconds
            storage.totalPresentNanoseconds &+= presentNanoseconds
            guard let renderReport else {
                storage.unattributedFrameCount &+= 1
                return
            }
            switch renderReport.path {
            case .fullScene:
                storage.fullSceneFrameCount &+= 1
            case .partialDamage:
                storage.partialDamageFrameCount &+= 1
            case .cachedAnimation:
                storage.cachedAnimationFrameCount &+= 1
            case .unknown:
                storage.unattributedFrameCount &+= 1
            }
        }
    }

    public func recordIdleSleep(milliseconds: UInt32) {
        lock.withLock {
            storage.idleSleepCount &+= 1
            storage.idleSleepMilliseconds &+= UInt64(milliseconds)
        }
    }

    public func recordSoftwarePacingSleep(milliseconds: UInt32) {
        lock.withLock {
            storage.softwarePacingSleepCount &+= 1
            storage.softwarePacingSleepMilliseconds &+= UInt64(milliseconds)
        }
    }

    public var snapshot: LunaRuntimeWorkAttributionSnapshot {
        lock.withLock { storage }
    }

    public func flushIfRequested() throws {
        guard let traceURL else { return }
        let parent = traceURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let temporaryURL = parent.appendingPathComponent(
            ".\(traceURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        try data.write(to: temporaryURL, options: .atomic)
        if FileManager.default.fileExists(atPath: traceURL.path) {
            _ = try FileManager.default.replaceItemAt(
                traceURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: traceURL)
        }
    }
}
