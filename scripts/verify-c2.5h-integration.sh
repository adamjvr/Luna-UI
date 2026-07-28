#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
required=(
  Sources/LunaUI/LunaStaticTextView.swift
  Sources/LunaUI/LunaStaticTextVirtualizedLayout.swift
  Tests/LunaUIPhase5F2ATests/LunaC25HLazyLineIndexTests.swift
  docs/C2.5H_LAZY_LINE_INDEX.md
)
for path in "${required[@]}"; do test -f "$path" || { echo "error: missing $path" >&2; exit 1; }; done
grep -Fq 'struct LunaStaticTextLineMetadata' Sources/LunaUI/LunaStaticTextView.swift
grep -Fq 'public func lineMetadata(at index: Int)' Sources/LunaUI/LunaStaticTextView.swift
grep -Fq 'presentation.document.utf8Count' Sources/LunaUI/LunaStaticTextVirtualizedLayout.swift
swift test --filter LunaC25HLazyLineIndexTests
swift test --filter LunaC25FVirtualizedTextLayoutTests
swift test --filter LunaRuntimeWorkAttributionTests
swift build
swift test
./scripts/validate-iteration.sh
git diff --check
