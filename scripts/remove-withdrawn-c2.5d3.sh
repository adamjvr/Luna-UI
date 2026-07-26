#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
withdrawn=(
  "C2.5D3_APPLY_AND_TEST.md"
  "C2.5D3_BASELINE.md"
  "Sources/LunaHostCore/LunaInputDispatchFairness.swift"
  "Tests/LunaHostSDLApplicationTests/LunaC25D3FrameFairnessTests.swift"
  "docs/C2.5D3_FRAME_FAIRNESS.md"
  "patches/C2.5D3_FRAME_FAIRNESS.patch"
  "scripts/verify-c2.5d3-frame-fairness.sh"
)
for path in "${withdrawn[@]}"; do
  if git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
    printf 'error: refusing to remove tracked file: %s\n' "$path" >&2
    exit 1
  fi
  if [[ -e "$path" || -L "$path" ]]; then
    rm -f -- "$path"
    printf 'removed withdrawn C2.5D3 file: %s\n' "$path"
  fi
done
printf '%s\n' 'Withdrawn C2.5D3 working files removed.'
