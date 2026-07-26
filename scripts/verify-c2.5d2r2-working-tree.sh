#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

runtime="Sources/LunaHostCore/LunaFrameRuntime.swift"
renderer="Sources/LunaUITestApp/DemoSharedRenderer.swift"

old_runtime_blob="3754a94f0ac1ecfbf8d8091624ce6135156ff18a"
old_renderer_blob="3ca24505a54fb1b91466d6740624d6bf584a87c3"

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_literal() {
    local file="$1"
    local literal="$2"
    local description="$3"
    grep -Fq -- "$literal" "$file" || \
        fail "$description is missing from $file"
}

require_absent_literal() {
    local file="$1"
    local literal="$2"
    local description="$3"
    if grep -Fq -- "$literal" "$file"; then
        fail "$description remains in $file"
    fi
}

git diff --quiet -- "$runtime" && \
    fail "$runtime has no working-tree source change"
git diff --quiet -- "$renderer" && \
    fail "$renderer has no working-tree source change"

new_runtime_blob="$(git hash-object "$runtime")"
new_renderer_blob="$(git hash-object "$renderer")"

[[ "$new_runtime_blob" != "$old_runtime_blob" ]] || \
    fail "$runtime still hashes to the pre-repair blob"
[[ "$new_renderer_blob" != "$old_renderer_blob" ]] || \
    fail "$renderer still hashes to the pre-repair blob"

require_literal \
    "$runtime" \
    '&+ renderPathCount(for: .partialDamage)' \
    'partial-damage cache-hit accounting'

require_literal \
    "$renderer" \
    'private var previousProofMovingBlockBounds' \
    'previous animation geometry retention'

require_literal \
    "$renderer" \
    'layout: cache.layout' \
    'cached-layout animation fast path'

require_literal \
    "$renderer" \
    'regions: damageRegions' \
    'bounded framebuffer restoration'

require_literal \
    "$renderer" \
    'path: .partialDamage' \
    'partial-damage frame reporting'

require_literal \
    "$renderer" \
    'damagedRegionCount: damageRegions.count' \
    'damaged-region diagnostics'

require_literal \
    "$renderer" \
    'damagedPixelCount: restoredPixels' \
    'damaged-pixel diagnostics'

require_absent_literal \
    "$renderer" \
    'fb.copyPixels(from: cache.framebuffer)' \
    'old whole-frame animation cache restore'

git diff --check -- "$runtime" "$renderer"

printf '%s\n' \
    'Luna C2.5D2R2 working-tree runtime integration verified.'
