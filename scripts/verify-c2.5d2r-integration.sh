#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

require_literal() {
    local file="$1"
    local literal="$2"
    local description="$3"

    if ! grep -Fq -- "$literal" "$file"; then
        printf 'error: missing C2.5D2R integration: %s\n' "$description" >&2
        printf '       expected in %s: %s\n' "$file" "$literal" >&2
        exit 1
    fi
}

require_absent_literal() {
    local file="$1"
    local literal="$2"
    local description="$3"

    if grep -Fq -- "$literal" "$file"; then
        printf 'error: stale pre-repair path remains: %s\n' "$description" >&2
        printf '       unexpected in %s: %s\n' "$file" "$literal" >&2
        exit 1
    fi
}

require_literal \
    Sources/LunaHostCore/LunaFrameRuntime.swift \
    '&+ renderPathCount(for: .partialDamage)' \
    'partial-damage frames must count as cache-backed hits'

require_literal \
    Sources/LunaUITestApp/DemoSharedRenderer.swift \
    'private var previousProofMovingBlockBounds' \
    'the Kitchen Sink must retain previous animation geometry'

require_literal \
    Sources/LunaUITestApp/DemoSharedRenderer.swift \
    'layout: cache.layout' \
    'the fast path must use cached layout instead of rebuilding the scene'

require_literal \
    Sources/LunaUITestApp/DemoSharedRenderer.swift \
    'regions: damageRegions' \
    'the static cache must restore bounded regions'

require_literal \
    Sources/LunaUITestApp/DemoSharedRenderer.swift \
    'path: .partialDamage' \
    'animation-only cache hits must report partial damage'

require_absent_literal \
    Sources/LunaUITestApp/DemoSharedRenderer.swift \
    'fb.copyPixels(from: cache.framebuffer)' \
    'the old complete-frame cache restore'

printf '%s\n' 'Luna C2.5D2R runtime integration verified.'
