// PublicAPI.swift
// Canonical public interface for Luna-UI

import LunaTheme

public enum LunaRendererMode {
    case gpu
    case cpu
    case auto
}

public protocol LunaEditorView {
    func setText(_ text: String)
    func applyTheme(_ theme: LunaTheme)
    func setRenderer(_ mode: LunaRendererMode)
    func resize(width: Int, height: Int)
    func draw()
}
