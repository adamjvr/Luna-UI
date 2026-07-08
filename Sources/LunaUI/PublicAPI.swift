// PublicAPI.swift
// Canonical public interface for Luna-UI

import Foundation
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaTheme
@_exported import LunaInput

/// CPU vs GPU selection for the renderer.
/// (GPU paths are platform-specific internally, but API is uniform.)
public enum LunaRendererMode: Sendable {
    case cpu
    case gpu
}

/// Public-facing editor view contract.
/// (Concrete implementations live in LunaHost/LunaUI internals.)
public protocol LunaEditorView {
    func setText(_ text: String)
    func applyTheme(_ theme: LunaTheme)
    func setRenderer(_ mode: LunaRendererMode)
    func resize(width: Int, height: Int)
}

/// Marker for the high-level Luna UI module.
public struct LunaUIModule {
    public init() {}
}
