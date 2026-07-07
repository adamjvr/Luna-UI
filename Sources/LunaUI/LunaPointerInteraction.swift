// LunaPointerInteraction.swift
//
// Phase 1B: small, platform-neutral pointer routing helpers.
//
// Host layers translate SDL/AppKit/etc. mouse events into these pure Luna
// events. Widgets stay platform-agnostic and can be tested without a window.

import Foundation
import LunaCommands
import LunaCore

/// Platform-neutral pointer button used by Luna's semantic interaction layer.
public enum LunaPointerButton: Hashable, Sendable {
    case primary
    case secondary
    case middle
    case other(Int)
}

/// Platform-neutral pointer event phase.
public enum LunaPointerPhase: Hashable, Sendable {
    case down
    case up
    case moved
}

/// Minimal pointer event shape needed to route Phase 1B widget activation.
public struct LunaPointerEvent: Hashable, Sendable {
    public var phase: LunaPointerPhase
    public var location: LunaPointI
    public var button: LunaPointerButton
    public var clickCount: Int

    public init(
        phase: LunaPointerPhase,
        location: LunaPointI,
        button: LunaPointerButton = .primary,
        clickCount: Int = 1
    ) {
        self.phase = phase
        self.location = location
        self.button = button
        self.clickCount = max(0, clickCount)
    }
}

/// Result of routing a pointer event through a semantic/actionable widget.
public struct LunaPointerActivationResult: Hashable, Sendable {
    public var event: LunaPointerEvent
    public var hitNodeID: LunaNodeID?
    public var requestedCommand: LunaCommandID?
    public var announcementTexts: [String]

    public init(
        event: LunaPointerEvent,
        hitNodeID: LunaNodeID?,
        requestedCommand: LunaCommandID?,
        announcementTexts: [String] = []
    ) {
        self.event = event
        self.hitNodeID = hitNodeID
        self.requestedCommand = requestedCommand
        self.announcementTexts = announcementTexts
    }

    public var didHit: Bool { hitNodeID != nil }
    public var didRequestCommand: Bool { requestedCommand != nil }
}

public extension LunaActionableWidget {
    /// Route a platform-neutral pointer event into this actionable widget.
    ///
    /// Only primary-button pointer-down activates the widget. Other pointer
    /// phases/buttons can still be routed later for hover, drag, context menus,
    /// etc., but Phase 1B keeps activation intentionally narrow and testable.
    @discardableResult
    mutating func handlePointerEvent(
        _ event: LunaPointerEvent,
        context: inout LunaUIContext
    ) -> LunaPointerActivationResult {
        guard event.phase == .down, event.button == .primary else {
            return LunaPointerActivationResult(
                event: event,
                hitNodeID: nil,
                requestedCommand: nil
            )
        }

        guard let hitNodeID = hitTest(event.location) else {
            return LunaPointerActivationResult(
                event: event,
                hitNodeID: nil,
                requestedCommand: nil
            )
        }

        let announcementStart = context.announcements.count
        let command = activate(context: &context)
        let newAnnouncements = context.announcements[announcementStart...].map(\.text)

        return LunaPointerActivationResult(
            event: event,
            hitNodeID: hitNodeID,
            requestedCommand: command,
            announcementTexts: Array(newAnnouncements)
        )
    }
}
