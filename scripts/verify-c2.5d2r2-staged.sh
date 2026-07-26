#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

required=(
    "Sources/LunaHostCore/LunaFrameRuntime.swift"
    "Sources/LunaUITestApp/DemoSharedRenderer.swift"
)

for file in "${required[@]}"; do
    git diff --cached --name-only | grep -Fxq "$file" || {
        printf 'error: required runtime source is not staged: %s\n' "$file" >&2
        exit 1
    }
done

staged_renderer="$(
    git show :Sources/LunaUITestApp/DemoSharedRenderer.swift
)"
staged_runtime="$(
    git show :Sources/LunaHostCore/LunaFrameRuntime.swift
)"

grep -Fq 'path: .partialDamage' <<<"$staged_renderer" || {
    printf '%s\n' \
        'error: staged DemoSharedRenderer.swift lacks .partialDamage' >&2
    exit 1
}

grep -Fq 'regions: damageRegions' <<<"$staged_renderer" || {
    printf '%s\n' \
        'error: staged DemoSharedRenderer.swift lacks bounded restoration' >&2
    exit 1
}

grep -Fq '&+ renderPathCount(for: .partialDamage)' <<<"$staged_runtime" || {
    printf '%s\n' \
        'error: staged LunaFrameRuntime.swift lacks partial hit accounting' >&2
    exit 1
}

git diff --cached --check

printf '%s\n' \
    'Luna C2.5D2R2 required runtime files are staged and verified.'
