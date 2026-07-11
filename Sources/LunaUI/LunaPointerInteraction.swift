// SPDX-License-Identifier: MPL-2.0
// LunaPointerInteraction.swift
//
// Phase 1B/2C: platform-neutral pointer routing helpers. The pointer event
// model lives in LunaInput so hosts can translate SDL/AppKit input below LunaUI.

import Foundation
import LunaCommands
import LunaCore
import LunaInput

/// Result of routing a pointer event through a semantic/actionable widget.
public struct LunaPointerActivationResult: Hashable, Sendable {
    public var event: LunaPointerEvent
    public var hitNodeID: LunaNodeID?
    public var requestedCommand: LunaCommandID?
    public var announcementTexts: [String]

    /// True when routing this event changed visible/transient UI state such as
    /// hover, press, overlay open/close, selection, caret position, or document
    /// content. Host runtimes should invalidate/redraw on state changes, not on
    /// mere geometric hits. This keeps pointer motion over stable chrome from
    /// becoming accidental continuous rendering.
    public var didChangeVisualState: Bool

    public init(
        event: LunaPointerEvent,
        hitNodeID: LunaNodeID?,
        requestedCommand: LunaCommandID?,
        announcementTexts: [String] = [],
        didChangeVisualState: Bool = false
    ) {
        self.event = event
        self.hitNodeID = hitNodeID
        self.requestedCommand = requestedCommand
        self.announcementTexts = announcementTexts
        self.didChangeVisualState = didChangeVisualState
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
