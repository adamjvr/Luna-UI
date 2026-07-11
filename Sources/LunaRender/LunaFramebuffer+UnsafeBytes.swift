// SPDX-License-Identifier: MPL-2.0
// LunaFramebuffer+UnsafeBytes.swift
//
// Purpose:
// - Provide a raw-pointer pixel upload helper for host presenters such as SDL.
//
// Design:
// - LunaFramebuffer's canonical public pixel API reports a typed UInt8 pointer
//   and row stride. Host upload APIs generally want an UnsafeRawPointer plus a
//   total byte count, so this adapter computes the byte count once and forwards
//   to the real storage-backed read-only API.
// - No reflection is used on the present path. Continuous proof-gallery frames
//   can therefore upload the CPU framebuffer without re-walking Swift metadata.

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
        let byteCount = self.bytesPerRow * self.height

        // This used to use Mirror as an early scaffold. That was convenient,
        // but it put reflection on every SDL present call, which is exactly the
        // wrong place for it once proof-gallery mode requests continuous frames.
        // Forward to LunaFramebuffer's real read-only pixel API instead.
        return self.withUnsafePixelBytes { (typedBase: UnsafePointer<UInt8>, _) -> R in
            body(UnsafeRawPointer(typedBase), byteCount)
        }
    }
}
