// SPDX-License-Identifier: MPL-2.0
// LunaDialogService.swift
//
// Product-neutral host dialog boundary.
//
// LunaUI owns document/workspace state and command routing, but native Open,
// Save, Save As, and unsaved-changes prompts are host/app responsibilities.
// This file deliberately lives in LunaHostCore so concrete apps can inject
// AppKit, Win32, XDG Portal, SDL, scripted, or test doubles without pulling
// platform dialog policy into LunaUI widgets.

import Foundation

// MARK: - Unsaved document confirmation

public enum LunaUnsavedChangesDecision: String, Hashable, Sendable, Codable {
    /// Save the document before closing. Untitled documents may require a Save
    /// destination dialog before the close can complete.
    case save

    /// Close without saving changes.
    case discard

    /// Abort the close request.
    case cancel
}

public struct LunaUnsavedChangesDialogRequest: Hashable, Sendable {
    public var documentID: String?
    public var title: String
    public var displayPath: String?
    public var isUntitled: Bool
    public var source: String?

    public init(
        documentID: String? = nil,
        title: String,
        displayPath: String? = nil,
        isUntitled: Bool = false,
        source: String? = nil
    ) {
        self.documentID = documentID
        self.title = title
        self.displayPath = displayPath
        self.isUntitled = isUntitled
        self.source = source
    }
}

public struct LunaUnsavedChangesDialogResult: Hashable, Sendable {
    public var decision: LunaUnsavedChangesDecision
    public var statusMessage: String?

    public init(decision: LunaUnsavedChangesDecision, statusMessage: String? = nil) {
        self.decision = decision
        self.statusMessage = statusMessage
    }

    public static func save(_ message: String? = nil) -> LunaUnsavedChangesDialogResult {
        LunaUnsavedChangesDialogResult(decision: .save, statusMessage: message)
    }

    public static func discard(_ message: String? = nil) -> LunaUnsavedChangesDialogResult {
        LunaUnsavedChangesDialogResult(decision: .discard, statusMessage: message)
    }

    public static func cancel(_ message: String? = nil) -> LunaUnsavedChangesDialogResult {
        LunaUnsavedChangesDialogResult(decision: .cancel, statusMessage: message)
    }
}

// MARK: - File chooser request/result

public enum LunaFileDialogPurpose: String, Hashable, Sendable, Codable {
    case open
    case save
}

public enum LunaFileDialogOutcome: String, Hashable, Sendable, Codable {
    case selected
    case cancelled
    case unavailable
    case failed
}

public struct LunaFileDialogRequest: Hashable, Sendable {
    public var purpose: LunaFileDialogPurpose
    public var title: String
    public var message: String?
    public var defaultDirectory: String?
    public var defaultFileName: String?
    public var allowedExtensions: [String]
    public var allowsMultipleSelection: Bool
    public var source: String?

    public init(
        purpose: LunaFileDialogPurpose,
        title: String,
        message: String? = nil,
        defaultDirectory: String? = nil,
        defaultFileName: String? = nil,
        allowedExtensions: [String] = [],
        allowsMultipleSelection: Bool = false,
        source: String? = nil
    ) {
        self.purpose = purpose
        self.title = title
        self.message = message
        self.defaultDirectory = defaultDirectory
        self.defaultFileName = defaultFileName
        self.allowedExtensions = allowedExtensions
        self.allowsMultipleSelection = allowsMultipleSelection
        self.source = source
    }
}

public struct LunaFileDialogResult: Hashable, Sendable {
    public var outcome: LunaFileDialogOutcome
    public var selectedPaths: [String]
    public var allowsOverwrite: Bool
    public var providerName: String?
    public var statusMessage: String?

    public init(
        outcome: LunaFileDialogOutcome,
        selectedPaths: [String] = [],
        allowsOverwrite: Bool = false,
        providerName: String? = nil,
        statusMessage: String? = nil
    ) {
        self.outcome = outcome
        self.selectedPaths = selectedPaths
        self.allowsOverwrite = allowsOverwrite
        self.providerName = providerName
        self.statusMessage = statusMessage
    }

    public var didSelect: Bool { outcome == .selected && !selectedPaths.isEmpty }
    public var firstSelectedPath: String? { selectedPaths.first }

    public static func selected(
        _ paths: [String],
        allowsOverwrite: Bool = false,
        providerName: String? = nil,
        statusMessage: String? = nil
    ) -> LunaFileDialogResult {
        LunaFileDialogResult(
            outcome: .selected,
            selectedPaths: paths,
            allowsOverwrite: allowsOverwrite,
            providerName: providerName,
            statusMessage: statusMessage
        )
    }

    public static func cancelled(_ message: String? = nil, providerName: String? = nil) -> LunaFileDialogResult {
        LunaFileDialogResult(outcome: .cancelled, providerName: providerName, statusMessage: message)
    }

    public static func unavailable(_ message: String? = nil, providerName: String? = nil) -> LunaFileDialogResult {
        LunaFileDialogResult(outcome: .unavailable, providerName: providerName, statusMessage: message)
    }

    public static func failed(_ message: String, providerName: String? = nil) -> LunaFileDialogResult {
        LunaFileDialogResult(outcome: .failed, providerName: providerName, statusMessage: message)
    }
}

// MARK: - Dialog service protocol

public protocol LunaDialogService {
    /// Human-readable provider name suitable for diagnostics/status bars.
    var providerDescription: String { get }

    mutating func confirmUnsavedChanges(_ request: LunaUnsavedChangesDialogRequest) -> LunaUnsavedChangesDialogResult
    mutating func chooseFileToOpen(_ request: LunaFileDialogRequest) -> LunaFileDialogResult
    mutating func chooseFileToSave(_ request: LunaFileDialogRequest) -> LunaFileDialogResult
}

/// Safe default for headless hosts and tests that have not installed an
/// explicit dialog double. It never fabricates paths and never discards user
/// edits automatically.
public struct LunaNoOpDialogService: LunaDialogService, Hashable, Sendable {
    public var providerDescription: String

    public init(providerDescription: String = "no native dialog service") {
        self.providerDescription = providerDescription
    }

    public mutating func confirmUnsavedChanges(_ request: LunaUnsavedChangesDialogRequest) -> LunaUnsavedChangesDialogResult {
        .cancel("No dialog service is available to confirm closing \(request.title)")
    }

    public mutating func chooseFileToOpen(_ request: LunaFileDialogRequest) -> LunaFileDialogResult {
        .unavailable("No dialog service is available for Open…", providerName: providerDescription)
    }

    public mutating func chooseFileToSave(_ request: LunaFileDialogRequest) -> LunaFileDialogResult {
        .unavailable("No dialog service is available for Save As…", providerName: providerDescription)
    }
}

/// Deterministic dialog double used by tests and scripted demo runs. It is also
/// the deliberate seam for future in-Luna file-browser widgets: such widgets can
/// satisfy this protocol without changing the document/workspace command path.
public struct LunaScriptedDialogService: LunaDialogService, Hashable, Sendable {
    public var providerDescription: String
    public var unsavedDecisions: [LunaUnsavedChangesDecision]
    public var openPathSelections: [[String]]
    public var savePathSelections: [String]
    public var scriptedSelectionsAllowOverwrite: Bool
    public var fallback: LunaNoOpDialogService

    public init(
        providerDescription: String = "scripted dialog service",
        unsavedDecisions: [LunaUnsavedChangesDecision] = [],
        openPathSelections: [[String]] = [],
        savePathSelections: [String] = [],
        scriptedSelectionsAllowOverwrite: Bool = false,
        fallback: LunaNoOpDialogService = LunaNoOpDialogService()
    ) {
        self.providerDescription = providerDescription
        self.unsavedDecisions = unsavedDecisions
        self.openPathSelections = openPathSelections
        self.savePathSelections = savePathSelections
        self.scriptedSelectionsAllowOverwrite = scriptedSelectionsAllowOverwrite
        self.fallback = fallback
    }

    public var hasScriptedUnsavedDecision: Bool { !unsavedDecisions.isEmpty }
    public var hasScriptedOpenSelection: Bool { !openPathSelections.isEmpty }
    public var hasScriptedSaveSelection: Bool { !savePathSelections.isEmpty }

    public mutating func confirmUnsavedChanges(_ request: LunaUnsavedChangesDialogRequest) -> LunaUnsavedChangesDialogResult {
        guard !unsavedDecisions.isEmpty else {
            return fallback.confirmUnsavedChanges(request)
        }
        let decision = unsavedDecisions.removeFirst()
        return LunaUnsavedChangesDialogResult(
            decision: decision,
            statusMessage: "Scripted unsaved-changes decision: \(decision.rawValue) for \(request.title)"
        )
    }

    public mutating func chooseFileToOpen(_ request: LunaFileDialogRequest) -> LunaFileDialogResult {
        guard !openPathSelections.isEmpty else {
            return fallback.chooseFileToOpen(request)
        }
        let paths = openPathSelections.removeFirst()
        guard !paths.isEmpty else {
            return .cancelled("Scripted Open… dialog cancelled", providerName: providerDescription)
        }
        return .selected(
            paths,
            allowsOverwrite: false,
            providerName: providerDescription,
            statusMessage: "Scripted Open… selected \(paths.count) path(s)"
        )
    }

    public mutating func chooseFileToSave(_ request: LunaFileDialogRequest) -> LunaFileDialogResult {
        guard !savePathSelections.isEmpty else {
            return fallback.chooseFileToSave(request)
        }
        let path = savePathSelections.removeFirst()
        guard !path.isEmpty else {
            return .cancelled("Scripted Save As… dialog cancelled", providerName: providerDescription)
        }
        return .selected(
            [path],
            allowsOverwrite: scriptedSelectionsAllowOverwrite,
            providerName: providerDescription,
            statusMessage: "Scripted Save As… selected \(path)"
        )
    }
}
