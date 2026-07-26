#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

swift test --filter LunaA1AuditTests
swift test --filter LunaA1PerformanceInvestigationTests
swift test --filter LunaInputDispatchFairnessTests
