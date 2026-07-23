#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -n "$(git status --porcelain)" ]]; then
        printf 'Notice: Luna UI working tree contains changes being validated.\n' >&2
    fi
    git diff HEAD --check
fi

if ! command -v pkg-config >/dev/null 2>&1; then
    printf 'error: pkg-config is required to validate Luna UI.\n' >&2
    exit 1
fi

for package in sdl2 harfbuzz freetype2; do
    if ! pkg-config --exists "$package"; then
        printf 'error: required pkg-config package is unavailable: %s\n' "$package" >&2
        exit 1
    fi
done

printf '%s\n' '==> Swift toolchain'
swift --version

printf '%s\n' '==> Native dependency versions'
printf 'SDL2 %s\n' "$(pkg-config --modversion sdl2)"
printf 'HarfBuzz %s\n' "$(pkg-config --modversion harfbuzz)"
printf 'FreeType %s\n' "$(pkg-config --modversion freetype2)"

printf '%s\n' '==> Building Luna UI and all test products'
swift build --build-tests

printf '%s\n' '==> Running complete Luna UI test suite'
swift test

printf '%s\n' 'Luna UI build and test validation passed.'
