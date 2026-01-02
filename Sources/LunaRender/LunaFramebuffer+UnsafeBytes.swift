// LunaFramebuffer+UnsafeBytes.swift
//
// Purpose:
// - Provide a stable way for host presenters (SDL, etc.) to access raw pixel bytes
//   without depending on the *internal* storage property name of LunaFramebuffer.
//
// Why:
// - Your LunaFramebuffer apparently does NOT expose a `pixels` member.
// - Different implementations may store pixels as [UInt8], [UInt32], Data, or a raw pointer.
// - The host layer just needs "a pointer + length" to upload to the OS / GPU.
//
// Design:
// - Primary API is `withUnsafePixelBytes(_:)` returning Void to avoid "unused result" warnings.
// - Secondary API `withUnsafePixelBytesResult(_:)` is available if you truly need a return value.
//
// IMPORTANT:
// - This uses reflection (Mirror) as a pragmatic scaffold.
// - Later, formalize pixel storage on LunaFramebuffer and delete this file.

import Foundation

public extension LunaFramebuffer {

    /// Execute `body` with a pointer to the framebuffer's pixel bytes.
    ///
    /// - Parameter body: Called with (baseAddress, byteCount).
    ///
    /// Safety:
    /// - The pointer is only valid for the duration of the closure.
    /// - Do NOT store the pointer.
    @inline(__always)
    func withUnsafePixelBytes(_ body: (UnsafeRawPointer, Int) -> Void) {
        withUnsafePixelBytesResult { ptr, count in
            body(ptr, count)
            return ()
        }
    }

    /// Same as `withUnsafePixelBytes(_:)`, but allows returning a value.
    /// Use this only when needed.
    @inline(__always)
    func withUnsafePixelBytesResult<R>(_ body: (UnsafeRawPointer, Int) -> R) -> R {

        // Common, stable byteCount if you have bytesPerRow/height.
        let byteCount = self.bytesPerRow * self.height

        let mirror = Mirror(reflecting: self)

        // 1) Try raw pointer-like storage
        for child in mirror.children {
            if let p = child.value as? UnsafeRawPointer {
                return body(p, byteCount)
            }
            if let p = child.value as? UnsafeMutableRawPointer {
                return body(UnsafeRawPointer(p), byteCount)
            }
        }

        // 2) Try [UInt8]
        for child in mirror.children {
            if let arr = child.value as? [UInt8] {
                return arr.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else {
                        fatalError("LunaFramebuffer storage [UInt8] is empty (no baseAddress).")
                    }
                    return body(base, byteCount)
                }
            }
        }

        // 3) Try [UInt32]
        for child in mirror.children {
            if let arr = child.value as? [UInt32] {
                return arr.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else {
                        fatalError("LunaFramebuffer storage [UInt32] is empty (no baseAddress).")
                    }
                    return body(base, byteCount)
                }
            }
        }

        // 4) Try Data
        for child in mirror.children {
            if let data = child.value as? Data {
                return data.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else {
                        fatalError("LunaFramebuffer storage Data is empty (no baseAddress).")
                    }
                    return body(base, byteCount)
                }
            }
        }

        fatalError("""
        LunaFramebuffer.withUnsafePixelBytes: could not locate pixel storage via reflection.

        Expected one of:
        - UnsafeRawPointer / UnsafeMutableRawPointer field
        - [UInt8] field
        - [UInt32] field
        - Data field

        Next step (recommended):
        - Expose an explicit pixel storage API on LunaFramebuffer and remove this reflection shim.
        """)
    }
}
