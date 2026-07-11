// SPDX-License-Identifier: MPL-2.0
// LunaMetrics.swift
//
// Centralized UI sizing. Luna widgets should derive chrome/padding/caret/menu
// dimensions from this instead of scattering fixed pixel constants everywhere.

import Foundation

public struct LunaMetrics: Hashable, Sendable {
    public var pointSize: Double
    public var dpiScale: Double
    public var lineHeight: Int
    public var padding: Int
    public var gutterWidth: Int
    public var scrollbarWidth: Int
    public var caretWidth: Int
    public var menuHeight: Int
    public var titleBarHeight: Int
    public var statusBarHeight: Int

    public init(
        pointSize: Double = 13,
        dpiScale: Double = 1,
        lineHeight: Int = 18,
        padding: Int = 8,
        gutterWidth: Int = 52,
        scrollbarWidth: Int = 12,
        caretWidth: Int = 2,
        menuHeight: Int = 28,
        titleBarHeight: Int = 34,
        statusBarHeight: Int = 24
    ) {
        self.pointSize = pointSize
        self.dpiScale = dpiScale
        self.lineHeight = lineHeight
        self.padding = padding
        self.gutterWidth = gutterWidth
        self.scrollbarWidth = scrollbarWidth
        self.caretWidth = caretWidth
        self.menuHeight = menuHeight
        self.titleBarHeight = titleBarHeight
        self.statusBarHeight = statusBarHeight
    }

    public static let `default` = LunaMetrics()
}
