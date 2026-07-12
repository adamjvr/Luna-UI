// SPDX-License-Identifier: MPL-2.0
// LunaCursorIntent.swift
//
// Platform-neutral native-pointer presentation requested by a Luna-hosted scene.

/// Semantic native cursor requested by the currently hovered or captured Luna
/// surface. Concrete hosts map these cases to platform cursor resources.
public enum LunaCursorIntent: String, Hashable, Sendable, CaseIterable {
    case arrow
    case text
    case resizeHorizontal
    case resizeVertical
    case pointingHand
    case prohibited
}
