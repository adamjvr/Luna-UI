#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${LUNA_A1_OUTPUT_DIR:-.build/a1.1r-luna-investigation}"
mkdir -p "$OUTPUT_DIR"

LUNA_RUN_A1_PERFORMANCE_PROBE=1 \
LUNA_A1_OUTPUT_DIR="$OUTPUT_DIR" \
swift test --filter LunaA1PerformanceInvestigationTests/testFullInvestigationMatrixWhenExplicitlyEnabled

printf '\nA1.1R Luna investigation written to: %s\n' "$OUTPUT_DIR"
