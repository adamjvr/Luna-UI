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

committed_runtime_blob="$(git rev-parse "HEAD:$runtime")"
committed_renderer_blob="$(git rev-parse "HEAD:$renderer")"

[[ "$committed_runtime_blob" != "$old_runtime_blob" ]] || \
    fail "$runtime was not committed; HEAD still contains the old blob"
[[ "$committed_renderer_blob" != "$old_renderer_blob" ]] || \
    fail "$renderer was not committed; HEAD still contains the old blob"

changed_files="$(git diff-tree --no-commit-id --name-only -r HEAD)"
grep -Fxq "$runtime" <<<"$changed_files" || \
    fail "latest commit does not include $runtime"
grep -Fxq "$renderer" <<<"$changed_files" || \
    fail "latest commit does not include $renderer"

git show "HEAD:$runtime" \
    | grep -Fq '&+ renderPathCount(for: .partialDamage)' || \
    fail "committed runtime lacks partial-damage hit accounting"

git show "HEAD:$renderer" \
    | grep -Fq 'path: .partialDamage' || \
    fail "committed renderer lacks partial-damage reporting"

git show "HEAD:$renderer" \
    | grep -Fq 'regions: damageRegions' || \
    fail "committed renderer lacks bounded cache restoration"

git show "HEAD:$renderer" \
    | grep -Fq 'layout: cache.layout' || \
    fail "committed renderer lacks the cached-layout fast path"

git show "HEAD:$renderer" \
    | grep -Fq 'damagedPixelCount: restoredPixels' || \
    fail "committed renderer lacks damage diagnostics"

if git show "HEAD:$renderer" \
    | grep -Fq 'fb.copyPixels(from: cache.framebuffer)'; then
    fail "committed renderer still contains the old whole-frame restore"
fi

printf '%s\n' \
    'Luna C2.5D2R2 committed runtime integration verified.'
printf 'HEAD: %s\n' "$(git rev-parse HEAD)"
printf 'runtime blob:  %s\n' "$committed_runtime_blob"
printf 'renderer blob: %s\n' "$committed_renderer_blob"
