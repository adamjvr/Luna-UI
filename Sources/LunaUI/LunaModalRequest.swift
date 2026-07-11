// SPDX-License-Identifier: MPL-2.0
// LunaModalRequest.swift
//
// Typed transient UI requests. App/editor logic asks Luna to open one of these;
// Luna owns presentation, focus routing, and accessibility exposure.

import Foundation
import LunaCommands
import LunaCore

public enum LunaModalRequest: Hashable, Sendable {
    case prompt(LunaPromptRequest)
    case list(LunaListRequest)
    case confirm(LunaConfirmRequest)
    case notice(LunaNoticeRequest)
    case completion(LunaCompletionRequest)
}

public struct LunaPromptRequest: Hashable, Sendable {
    public var id: LunaNodeID
    public var title: String
    public var placeholder: String
    public var initialText: String
    public var commandOnSubmit: LunaCommandID

    public init(
        id: LunaNodeID,
        title: String,
        placeholder: String = "",
        initialText: String = "",
        commandOnSubmit: LunaCommandID
    ) {
        self.id = id
        self.title = title
        self.placeholder = placeholder
        self.initialText = initialText
        self.commandOnSubmit = commandOnSubmit
    }
}

public struct LunaListRequest: Hashable, Sendable {
    public var id: LunaNodeID
    public var title: String
    public var items: [String]
    public var commandOnPick: LunaCommandID

    public init(id: LunaNodeID, title: String, items: [String], commandOnPick: LunaCommandID) {
        self.id = id
        self.title = title
        self.items = items
        self.commandOnPick = commandOnPick
    }
}

public struct LunaConfirmRequest: Hashable, Sendable {
    public var id: LunaNodeID
    public var title: String
    public var message: String
    public var buttons: [String]
    public var commandOnChoice: LunaCommandID

    public init(id: LunaNodeID, title: String, message: String, buttons: [String], commandOnChoice: LunaCommandID) {
        self.id = id
        self.title = title
        self.message = message
        self.buttons = buttons
        self.commandOnChoice = commandOnChoice
    }
}

public struct LunaNoticeRequest: Hashable, Sendable {
    public var id: LunaNodeID
    public var title: String
    public var message: String

    public init(id: LunaNodeID, title: String, message: String) {
        self.id = id
        self.title = title
        self.message = message
    }
}

public struct LunaCompletionRequest: Hashable, Sendable {
    public var id: LunaNodeID
    public var anchor: LunaNodeID
    public var items: [String]
    public var commandOnPick: LunaCommandID

    public init(id: LunaNodeID, anchor: LunaNodeID, items: [String], commandOnPick: LunaCommandID) {
        self.id = id
        self.anchor = anchor
        self.items = items
        self.commandOnPick = commandOnPick
    }
}
