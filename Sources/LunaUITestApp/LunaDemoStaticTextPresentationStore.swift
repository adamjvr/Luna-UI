// SPDX-License-Identifier: MPL-2.0
//
// LunaDemoStaticTextPresentationStore.swift
//
// C2.5G: revision-keyed reuse of one presentation and one virtualization
// context across both demo panes.

import Foundation
import LunaUI

struct LunaDemoStaticTextPresentationBundle {
    let presentation: LunaStaticTextPresentationSnapshot
    let virtualizationContext: LunaStaticTextVirtualizationContext
}

struct LunaDemoStaticTextPresentationDiagnostics: Hashable, Sendable {
    var buildCount: UInt64 = 0
    var cacheHitCount: UInt64 = 0
}

final class LunaDemoStaticTextPresentationStore: @unchecked Sendable {
    private let lock = NSLock()
    private var revisionKey: AnyHashable?
    private var bundle: LunaDemoStaticTextPresentationBundle?
    private var nextPresentationRevision: UInt64 = 0
    private var diagnosticsStorage = LunaDemoStaticTextPresentationDiagnostics()

    func presentation<Revision: Hashable>(
        revision: Revision,
        document: LunaStaticTextDocument,
        geometryGeneration: UInt64 = 0
    ) -> LunaDemoStaticTextPresentationBundle {
        let key = AnyHashable(revision)
        return lock.withLock {
            if revisionKey == key, let bundle {
                diagnosticsStorage.cacheHitCount &+= 1
                return bundle
            }

            nextPresentationRevision &+= 1
            let presentation = LunaStaticTextPresentationSnapshot(
                revision: nextPresentationRevision,
                document: document
            )
            let newBundle = LunaDemoStaticTextPresentationBundle(
                presentation: presentation,
                virtualizationContext: LunaStaticTextVirtualizationContext(
                    presentation: presentation,
                    geometryGeneration: geometryGeneration
                )
            )
            revisionKey = key
            bundle = newBundle
            diagnosticsStorage.buildCount &+= 1
            return newBundle
        }
    }

    var diagnostics: LunaDemoStaticTextPresentationDiagnostics {
        lock.withLock { diagnosticsStorage }
    }

    func removeAll() {
        lock.withLock {
            revisionKey = nil
            bundle = nil
        }
    }
}
