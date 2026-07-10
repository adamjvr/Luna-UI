// LunaCommandRuntime.swift
//
// Product-neutral command execution, availability, key binding, and surface
// projection primitives.
//
// LunaCommands owns the common command vocabulary and routing machinery that can
// be shared by menus, context menus, command palettes, keymaps, accessibility
// actions, and future editor chrome. Applications still own policy and handlers:
// Luna does not decide how a file saves, how a project is structured, or what a
// product-specific command means.

import Foundation
import LunaCore

// MARK: - Command context

/// Product-neutral command execution context.
///
/// The context deliberately carries simple metadata rather than app objects. A
/// host application can encode the currently focused surface, active document,
/// and small string attributes while keeping real editor/project/file state in
/// the mutable host passed to `LunaCommandRuntime.execute`.
public struct LunaCommandContext: Hashable, Sendable {
    public var focusedSurface: String?
    public var activeDocumentID: String?
    public var source: String?
    public var attributes: [String: String]

    public init(
        focusedSurface: String? = nil,
        activeDocumentID: String? = nil,
        source: String? = nil,
        attributes: [String: String] = [:]
    ) {
        self.focusedSurface = focusedSurface
        self.activeDocumentID = activeDocumentID
        self.source = source
        self.attributes = attributes
    }

    public func value(for key: String) -> String? {
        attributes[key]
    }

    public func integerValue(for key: String) -> Int? {
        attributes[key].flatMap(Int.init)
    }

    public func withAttributes(_ additionalAttributes: [String: String]) -> LunaCommandContext {
        var copy = self
        for (key, value) in additionalAttributes {
            copy.attributes[key] = value
        }
        return copy
    }
}

public enum LunaCommandContextAttributeKey {
    /// Optional target document for commands that conceptually operate on a
    /// document other than the currently active document. Tab-close commands are
    /// the motivating case: clicking a close button should close the clicked tab,
    /// not whatever document happens to be active by the time the command runs.
    public static let targetDocumentID = "luna.target.documentID"

    /// Optional target file for workspace/project commands. This remains a plain
    /// string so LunaCommands does not depend on LunaUI workspace types.
    public static let targetFileID = "luna.target.fileID"

    /// Optional target shell tab ID for UI-shell commands that need to preserve
    /// the exact tab frame that initiated the action.
    public static let targetShellTabID = "luna.target.shellTabID"
}

public extension LunaCommandContext {
    /// Prefer an explicit target document when a command was invoked from a
    /// target-bearing UI surface such as a tab close button; otherwise fall back
    /// to the active document. Command handlers can use this to stay
    /// context-driven instead of baking per-document command IDs into menus.
    var targetOrActiveDocumentID: String? {
        attributes[LunaCommandContextAttributeKey.targetDocumentID] ?? activeDocumentID
    }

    var explicitTargetDocumentID: String? {
        attributes[LunaCommandContextAttributeKey.targetDocumentID]
    }
}

// MARK: - Availability and execution results

/// Dynamic command presentation state for the current host/context.
public struct LunaCommandAvailability: Hashable, Sendable {
    public var isEnabled: Bool
    public var isVisible: Bool
    public var isChecked: Bool
    public var titleOverride: String?
    public var disabledReason: String?

    public init(
        isEnabled: Bool = true,
        isVisible: Bool = true,
        isChecked: Bool = false,
        titleOverride: String? = nil,
        disabledReason: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.isVisible = isVisible
        self.isChecked = isChecked
        self.titleOverride = titleOverride
        self.disabledReason = disabledReason
    }

    public static let enabled = LunaCommandAvailability()
    public static let hidden = LunaCommandAvailability(isEnabled: false, isVisible: false)

    public static func disabled(_ reason: String? = nil, isVisible: Bool = true) -> LunaCommandAvailability {
        LunaCommandAvailability(isEnabled: false, isVisible: isVisible, disabledReason: reason)
    }

    public static func checked(_ isChecked: Bool = true) -> LunaCommandAvailability {
        LunaCommandAvailability(isChecked: isChecked)
    }
}

/// Result returned by command handlers.
public struct LunaCommandExecutionResult: Hashable, Sendable {
    public var didHandle: Bool
    public var statusMessage: String?
    public var announcementTexts: [String]
    public var followUpCommand: LunaCommandID?

    public init(
        didHandle: Bool = true,
        statusMessage: String? = nil,
        announcementTexts: [String] = [],
        followUpCommand: LunaCommandID? = nil
    ) {
        self.didHandle = didHandle
        self.statusMessage = statusMessage
        self.announcementTexts = announcementTexts
        self.followUpCommand = followUpCommand
    }

    public static func handled(_ statusMessage: String? = nil, announcements: [String] = []) -> LunaCommandExecutionResult {
        LunaCommandExecutionResult(didHandle: true, statusMessage: statusMessage, announcementTexts: announcements)
    }

    public static func unhandled(_ statusMessage: String? = nil) -> LunaCommandExecutionResult {
        LunaCommandExecutionResult(didHandle: false, statusMessage: statusMessage)
    }
}

// MARK: - Key bindings

/// Platform-neutral key stroke used for command matching.
public struct LunaKeyStroke: Hashable, Sendable {
    public var key: String
    public var modifiers: Set<LunaKeyModifier>

    public init(_ key: String, modifiers: Set<LunaKeyModifier> = []) {
        self.key = key
        self.modifiers = modifiers
    }

    public var normalizedKey: String {
        LunaKeyStroke.normalizeKey(key)
    }

    public static func normalizeKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        return trimmed.count == 1 ? trimmed.lowercased() : trimmed.lowercased()
    }
}

public struct LunaKeyBinding: Hashable, Sendable {
    public var command: LunaCommandID
    public var keyEquivalent: LunaKeyEquivalent
    public var context: String?
    public var priority: Int

    public init(
        command: LunaCommandID,
        keyEquivalent: LunaKeyEquivalent,
        context: String? = nil,
        priority: Int = 0
    ) {
        self.command = command
        self.keyEquivalent = keyEquivalent
        self.context = context
        self.priority = priority
    }
}

public struct LunaKeyBindingMap: Hashable, Sendable {
    public var bindings: [LunaKeyBinding]

    public init(bindings: [LunaKeyBinding] = []) {
        self.bindings = bindings.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.command.rawValue < rhs.command.rawValue
        }
    }

    public mutating func add(_ binding: LunaKeyBinding) {
        bindings.append(binding)
        bindings.sort { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.command.rawValue < rhs.command.rawValue
        }
    }

    public func commands(matching stroke: LunaKeyStroke, context: LunaCommandContext = LunaCommandContext()) -> [LunaCommandID] {
        bindings.compactMap { binding in
            if let bindingContext = binding.context,
               let focused = context.focusedSurface,
               bindingContext != focused {
                return nil
            }
            return binding.keyEquivalent.matches(stroke) ? binding.command : nil
        }
    }

    public func firstCommand(matching stroke: LunaKeyStroke, context: LunaCommandContext = LunaCommandContext()) -> LunaCommandID? {
        commands(matching: stroke, context: context).first
    }
}

public extension LunaKeyEquivalent {
    /// A compatibility parser for older descriptors that stored display strings
    /// such as `Ctrl+P` in the key field. New code should prefer
    /// `LunaKeyEquivalent("P", modifiers: [.primary])`.
    var parsedForCommandMatching: LunaKeyEquivalent {
        guard modifiers.isEmpty, key.contains("+") else { return self }
        var parsedModifiers: Set<LunaKeyModifier> = []
        let parts = key.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let last = parts.last, !last.isEmpty else { return self }
        for part in parts.dropLast() {
            switch part.lowercased() {
            case "primary", "cmdorctrl", "ctrl", "control":
                parsedModifiers.insert(.primary)
            case "cmd", "command":
                parsedModifiers.insert(.command)
            case "option":
                parsedModifiers.insert(.option)
            case "alt":
                parsedModifiers.insert(.alt)
            case "shift":
                parsedModifiers.insert(.shift)
            case "super", "meta":
                parsedModifiers.insert(.super)
            default:
                break
            }
        }
        return LunaKeyEquivalent(last, modifiers: parsedModifiers)
    }

    func matches(_ stroke: LunaKeyStroke) -> Bool {
        let equivalent = parsedForCommandMatching
        guard LunaKeyStroke.normalizeKey(equivalent.key) == stroke.normalizedKey else { return false }

        let required = equivalent.modifiers
        let strokeModifiers = stroke.modifiers

        if required.contains(.primary) {
            let hasPrimaryConcrete = strokeModifiers.contains(.primary) || strokeModifiers.contains(.control) || strokeModifiers.contains(.command)
            guard hasPrimaryConcrete else { return false }
        } else {
            if strokeModifiers.contains(.primary) { return false }
        }

        func requiredContainsEither(_ lhs: LunaKeyModifier, _ rhs: LunaKeyModifier) -> Bool {
            required.contains(lhs) || required.contains(rhs)
        }

        if required.contains(.control), !strokeModifiers.contains(.control) { return false }
        if required.contains(.command), !strokeModifiers.contains(.command) { return false }
        if required.contains(.shift), !strokeModifiers.contains(.shift) { return false }
        if required.contains(.super), !strokeModifiers.contains(.super) { return false }

        if requiredContainsEither(.option, .alt) {
            guard strokeModifiers.contains(.option) || strokeModifiers.contains(.alt) else { return false }
        }

        let primaryAllowsControlCommand = required.contains(.primary)
        let optionAllowsEither = requiredContainsEither(.option, .alt)

        for modifier in strokeModifiers {
            switch modifier {
            case .primary:
                if !required.contains(.primary) { return false }
            case .control, .command:
                if !primaryAllowsControlCommand && !required.contains(modifier) { return false }
            case .option, .alt:
                if !optionAllowsEither && !required.contains(modifier) { return false }
            case .shift, .super:
                if !required.contains(modifier) { return false }
            }
        }

        return true
    }
}

// MARK: - Surface projection

/// A command resolved for presentation in a concrete UI surface.
public struct LunaCommandSurfaceItem: Hashable, Sendable {
    public var id: LunaCommandID
    public var title: String
    public var accessibilityLabel: String
    public var menuPath: [String]
    public var keyEquivalent: LunaKeyEquivalent?
    public var isEnabled: Bool
    public var isVisible: Bool
    public var isChecked: Bool
    public var disabledReason: String?

    public init(
        descriptor: LunaCommandDescriptor,
        availability: LunaCommandAvailability
    ) {
        self.id = descriptor.id
        self.title = availability.titleOverride ?? descriptor.title
        self.accessibilityLabel = descriptor.accessibilityLabel
        self.menuPath = descriptor.menuPath
        self.keyEquivalent = descriptor.defaultKey
        self.isEnabled = availability.isEnabled
        self.isVisible = availability.isVisible
        self.isChecked = availability.isChecked
        self.disabledReason = availability.disabledReason
    }
}

// MARK: - Runtime

public typealias LunaCommandHandler<Host> = (LunaCommandID, inout Host, LunaCommandContext) -> LunaCommandExecutionResult
public typealias LunaCommandAvailabilityProvider<Host> = (LunaCommandID, Host, LunaCommandContext) -> LunaCommandAvailability

/// Generic command runtime shared by products built on Luna.
///
/// The runtime is generic over the application host. Luna supplies routing,
/// descriptors, keymap matching, availability, and surface projection; the host
/// supplies the actual mutable state and command policy through closures.
public struct LunaCommandRuntime<Host> {
    public private(set) var registry: LunaCommandRegistry
    public private(set) var keyBindings: LunaKeyBindingMap

    private var handlers: [LunaCommandID: LunaCommandHandler<Host>] = [:]
    private var availabilityProviders: [LunaCommandID: LunaCommandAvailabilityProvider<Host>] = [:]

    public init(
        registry: LunaCommandRegistry = LunaCommandRegistry(),
        keyBindings: LunaKeyBindingMap = LunaKeyBindingMap()
    ) {
        self.registry = registry
        self.keyBindings = keyBindings
    }

    public var descriptors: [LunaCommandDescriptor] { registry.all }

    public mutating func register(
        _ descriptor: LunaCommandDescriptor,
        handler: LunaCommandHandler<Host>? = nil,
        availability: LunaCommandAvailabilityProvider<Host>? = nil
    ) {
        registry.register(descriptor)
        if let handler {
            handlers[descriptor.id] = handler
        }
        if let availability {
            availabilityProviders[descriptor.id] = availability
        }
        if let key = descriptor.defaultKey {
            keyBindings.add(LunaKeyBinding(command: descriptor.id, keyEquivalent: key))
        }
    }

    public mutating func register(
        contentsOf descriptors: some Sequence<LunaCommandDescriptor>,
        handler: LunaCommandHandler<Host>? = nil,
        availability: LunaCommandAvailabilityProvider<Host>? = nil
    ) {
        for descriptor in descriptors {
            register(descriptor, handler: handler, availability: availability)
        }
    }

    public mutating func registerKeyBinding(_ binding: LunaKeyBinding) {
        keyBindings.add(binding)
    }

    public func availability(
        for command: LunaCommandID,
        host: Host,
        context: LunaCommandContext = LunaCommandContext()
    ) -> LunaCommandAvailability {
        guard registry.contains(command) else {
            return .disabled("Unknown command")
        }
        return availabilityProviders[command]?(command, host, context) ?? .enabled
    }

    public func surfaceItem(
        for command: LunaCommandID,
        host: Host,
        context: LunaCommandContext = LunaCommandContext()
    ) -> LunaCommandSurfaceItem? {
        guard let descriptor = registry.descriptor(for: command) else { return nil }
        return LunaCommandSurfaceItem(descriptor: descriptor, availability: availability(for: command, host: host, context: context))
    }

    public func paletteDescriptors(
        host: Host,
        context: LunaCommandContext = LunaCommandContext(),
        includeDisabled: Bool = true
    ) -> [LunaCommandDescriptor] {
        registry.paletteVisible.compactMap { descriptor in
            let availability = availability(for: descriptor.id, host: host, context: context)
            guard availability.isVisible else { return nil }
            guard includeDisabled || availability.isEnabled else { return nil }
            if let title = availability.titleOverride {
                var copy = descriptor
                copy.title = title
                return copy
            }
            return descriptor
        }
    }

    public func command(
        matching stroke: LunaKeyStroke,
        host: Host,
        context: LunaCommandContext = LunaCommandContext()
    ) -> LunaCommandID? {
        for command in keyBindings.commands(matching: stroke, context: context) {
            let availability = availability(for: command, host: host, context: context)
            if availability.isVisible && availability.isEnabled {
                return command
            }
        }
        return nil
    }

    @discardableResult
    public func execute(
        _ command: LunaCommandID,
        host: inout Host,
        context: LunaCommandContext = LunaCommandContext()
    ) -> LunaCommandExecutionResult {
        guard let descriptor = registry.descriptor(for: command) else {
            return .unhandled("Unknown command: \(command.rawValue)")
        }
        let availability = self.availability(for: command, host: host, context: context)
        guard availability.isVisible else {
            return .unhandled("Hidden command: \(descriptor.title)")
        }
        guard availability.isEnabled else {
            return .unhandled(availability.disabledReason ?? "Disabled command: \(descriptor.title)")
        }
        guard let handler = handlers[command] else {
            return .unhandled("No handler registered for \(descriptor.title)")
        }
        return handler(command, &host, context)
    }
}
