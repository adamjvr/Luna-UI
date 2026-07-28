#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

required=(
  Sources/LunaHostCore/LunaRuntimeWorkAttribution.swift
  Sources/LunaHostSDL/LunaSDLPresenter.swift
  Sources/LunaHostSDL/LunaSDLApplication.swift
  Sources/LunaUITestApp/LunaDemoStaticTextPresentationStore.swift
  Sources/LunaUITestApp/DemoSharedRenderer.swift
  Tests/LunaHostPhase5C1Tests/LunaRuntimeWorkAttributionTests.swift
  docs/C2.5G_MEASURED_RUNTIME_ATTRIBUTION.md
)
for path in "${required[@]}"; do
  test -f "$path" || { echo "error: missing $path" >&2; exit 1; }
done

grep -Fq 'SDL_GetRendererInfo' Sources/LunaHostSDL/LunaSDLPresenter.swift
grep -Fq 'hasPresentVSync' Sources/LunaHostSDL/LunaSDLPresenter.swift
grep -Fq 'LunaRuntimeWorkAttributionRecorder' Sources/LunaHostSDL/LunaSDLApplication.swift
grep -Fq 'staticTextPresentationStore' Sources/LunaUITestApp/DemoSharedRenderer.swift
grep -Fq 'view.virtualizationContext' Sources/LunaUITestApp/DemoSharedRenderer.swift

swift test --filter LunaRuntimeWorkAttributionTests
swift test --filter LunaInputDispatchFairnessTests
swift test --filter LunaC25FVirtualizedTextLayoutTests
swift build
swift test
./scripts/validate-iteration.sh
git diff --check
