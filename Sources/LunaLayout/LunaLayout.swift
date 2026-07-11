// SPDX-License-Identifier: MPL-2.0
// LunaLayout.swift
//
// Phase 2D: small, explicit layout/reflow primitives.
//
// The key invariant for Luna widgets is:
//     draw bounds == hit-test bounds == accessibility bounds
//
// LunaLayout keeps those bounds deterministic when the host window changes
// size. This is intentionally modest: it is not a full flexbox/grid engine yet.
// It gives Luna a typed viewport, anchored frame computation, and a layout
// result container that the demo and tests can use before Phase 3 text views.

import Foundation
import LunaCore
import LunaRender

public struct LunaLayoutModule {
    public init() {}
}

/// Current drawable viewport in logical pixels.
public struct LunaViewport: Hashable, Sendable {
    public var size: LunaSizeI

    public init(size: LunaSizeI) {
        self.size = LunaSizeI(width: max(1, size.width), height: max(1, size.height))
    }

    public init(width: Int, height: Int) {
        self.init(size: LunaSizeI(width: width, height: height))
    }

    public var bounds: LunaRectI {
        LunaRectI(x: 0, y: 0, w: size.width, h: size.height)
    }
}

/// Layout context passed through root scene/widget reflow.
public struct LunaLayoutContext: Hashable, Sendable {
    public var viewport: LunaViewport
    public var safeArea: LunaInsetsI

    public init(viewport: LunaViewport, safeArea: LunaInsetsI = LunaInsetsI(0)) {
        self.viewport = viewport
        self.safeArea = safeArea
    }

    /// Bounds available after safe-area insets are applied.
    public var contentBounds: LunaRectI {
        let b = viewport.bounds
        return LunaRectI(
            x: b.x + safeArea.left,
            y: b.y + safeArea.top,
            w: max(1, b.w - safeArea.left - safeArea.right),
            h: max(1, b.h - safeArea.top - safeArea.bottom)
        )
    }
}

/// Common anchoring modes for compact editor chrome, panels, overlays, and
/// proof widgets.
public enum LunaLayoutAnchor: String, Hashable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case center
    case bottomLeft
    case bottomCenter
    case bottomRight
}

/// Preferred size information for a laid-out frame.
public struct LunaLayoutSizeRule: Hashable, Sendable {
    public var preferred: LunaSizeI
    public var minimum: LunaSizeI
    public var maximum: LunaSizeI?

    public init(
        preferred: LunaSizeI,
        minimum: LunaSizeI = LunaSizeI(width: 1, height: 1),
        maximum: LunaSizeI? = nil
    ) {
        self.preferred = preferred
        self.minimum = LunaSizeI(width: max(1, minimum.width), height: max(1, minimum.height))
        self.maximum = maximum.map { LunaSizeI(width: max(1, $0.width), height: max(1, $0.height)) }
    }

    public func resolved(inside available: LunaRectI) -> LunaSizeI {
        let maxW = maximum?.width ?? preferred.width
        let maxH = maximum?.height ?? preferred.height
        let w = min(max(minimum.width, preferred.width), max(1, min(maxW, available.w)))
        let h = min(max(minimum.height, preferred.height), max(1, min(maxH, available.h)))
        return LunaSizeI(width: w, height: h)
    }
}

/// A single anchored layout specification.
public struct LunaAnchoredLayoutSpec: Hashable, Sendable {
    public var id: LunaNodeID
    public var anchor: LunaLayoutAnchor
    public var sizeRule: LunaLayoutSizeRule
    public var margin: LunaInsetsI

    public init(
        id: LunaNodeID,
        anchor: LunaLayoutAnchor,
        sizeRule: LunaLayoutSizeRule,
        margin: LunaInsetsI = LunaInsetsI(0)
    ) {
        self.id = id
        self.anchor = anchor
        self.sizeRule = sizeRule
        self.margin = margin
    }

    public func frame(in context: LunaLayoutContext) -> LunaLayoutFrame {
        let content = context.contentBounds
        let available = LunaRectI(
            x: content.x + margin.left,
            y: content.y + margin.top,
            w: max(1, content.w - margin.left - margin.right),
            h: max(1, content.h - margin.top - margin.bottom)
        )
        let size = sizeRule.resolved(inside: available)

        let x: Int
        switch anchor {
        case .topLeft, .bottomLeft:
            x = available.x
        case .topCenter, .center, .bottomCenter:
            x = available.x + max(0, (available.w - size.width) / 2)
        case .topRight, .bottomRight:
            x = available.x + max(0, available.w - size.width)
        }

        let y: Int
        switch anchor {
        case .topLeft, .topCenter, .topRight:
            y = available.y
        case .center:
            y = available.y + max(0, (available.h - size.height) / 2)
        case .bottomLeft, .bottomCenter, .bottomRight:
            y = available.y + max(0, available.h - size.height)
        }

        return LunaLayoutFrame(id: id, bounds: LunaRectI(x: x, y: y, w: size.width, h: size.height))
    }
}

/// Concrete frame produced by layout.
public struct LunaLayoutFrame: Hashable, Sendable {
    public var id: LunaNodeID
    public var bounds: LunaRectI

    public init(id: LunaNodeID, bounds: LunaRectI) {
        self.id = id
        self.bounds = bounds
    }
}

/// Container for frame results. It keeps the demo/tests honest: rendering,
/// hit testing, and accessibility should read their geometry from the same
/// computed frames.
public struct LunaLayoutResult: Hashable, Sendable {
    public private(set) var frames: [LunaNodeID: LunaRectI]

    public init(frames: [LunaNodeID: LunaRectI] = [:]) {
        self.frames = frames
    }

    public mutating func set(_ frame: LunaLayoutFrame) {
        frames[frame.id] = frame.bounds
    }

    public mutating func set(id: LunaNodeID, bounds: LunaRectI) {
        frames[id] = bounds
    }

    public func frame(for id: LunaNodeID) -> LunaRectI? {
        frames[id]
    }
}
