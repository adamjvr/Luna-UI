// LunaUIContext.swift
//
// The controlled boundary between an application and the Luna
// runtime. App logic records intent here; the host/runtime later flushes that
// intent into visible UI, accessibility updates, and redraws.

import Foundation
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaTheme

public struct LunaUIContext: Sendable {
    public private(set) var title: String?
    public private(set) var statusLeft: String?
    public private(set) var statusRight: String?
    public private(set) var requestedTheme: LunaTheme?
    public private(set) var requestedRefresh: Bool = false
    public private(set) var requestedCommands: [LunaCommandID] = []
    public private(set) var modalRequests: [LunaModalRequest] = []
    public private(set) var announcements: [LunaLiveAnnouncement] = []

    public init() {}

    public mutating func setTitle(_ title: String) {
        self.title = title
        requestRefresh()
    }

    public mutating func setStatus(left: String? = nil, right: String? = nil) {
        self.statusLeft = left
        self.statusRight = right
        requestRefresh()
    }

    public mutating func setTheme(_ theme: LunaTheme) {
        self.requestedTheme = theme
        requestRefresh()
    }

    public mutating func requestRefresh() {
        self.requestedRefresh = true
    }

    /// Queue an application command requested by a semantic widget.
    ///
    /// Luna does not execute commands itself. The app/runtime drains this queue
    /// and dispatches through its command table, keeping widgets independent
    /// from editor/product policy.
    public mutating func requestCommand(_ id: LunaCommandID) {
        requestedCommands.append(id)
        requestRefresh()
    }

    public mutating func announce(_ text: String, politeness: LunaAccessibilityPoliteness = .polite) {
        guard !text.isEmpty else { return }
        announcements.append(LunaLiveAnnouncement(text, politeness: politeness))
    }

    public mutating func openPrompt(_ request: LunaPromptRequest) {
        modalRequests.append(.prompt(request))
        requestRefresh()
    }

    public mutating func openList(_ request: LunaListRequest) {
        modalRequests.append(.list(request))
        requestRefresh()
    }

    public mutating func openConfirm(_ request: LunaConfirmRequest) {
        modalRequests.append(.confirm(request))
        requestRefresh()
    }

    public mutating func openNotice(_ request: LunaNoticeRequest) {
        modalRequests.append(.notice(request))
        requestRefresh()
    }

    public mutating func openCompletion(_ request: LunaCompletionRequest) {
        modalRequests.append(.completion(request))
        requestRefresh()
    }

    /// Drain queued modal requests so a runtime/overlay manager can open them.
    ///
    /// LunaUIContext records intent; runtime layers consume that intent at frame
    /// boundaries.  This keeps application logic from directly owning overlay
    /// presentation state.
    public mutating func drainModalRequests() -> [LunaModalRequest] {
        let requests = modalRequests
        modalRequests.removeAll()
        return requests
    }

    /// Drain queued command requests after the application has dispatched them.
    public mutating func drainRequestedCommands() -> [LunaCommandID] {
        let commands = requestedCommands
        requestedCommands.removeAll()
        return commands
    }

}
