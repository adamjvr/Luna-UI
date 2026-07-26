#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
expected_branch="a1.1-measured-audit"
expected_head="0e187d03fda59be094ed1746bb2282017cba8991"
expected_runtime_blob="3754a94f0ac1ecfbf8d8091624ce6135156ff18a"
expected_renderer_blob="3ca24505a54fb1b91466d6740624d6bf584a87c3"
patch_file="patches/C2.5D2R2_LUNA_VERIFIED_RUNTIME_INTEGRATION.patch"
fail(){ printf 'error: %s\n' "$*" >&2; exit 1; }
branch="$(git branch --show-current)"
[[ "$branch" == "$expected_branch" ]] || fail "expected branch $expected_branch, found ${branch:-detached HEAD}"
head_sha="$(git rev-parse HEAD)"
[[ "$head_sha" == "$expected_head" ]] || fail "expected C2.5D2R commit $expected_head, found $head_sha"
git diff --quiet || fail "tracked working-tree changes already exist; commit or restore them first"
git diff --cached --quiet || fail "staged changes already exist; commit or unstage them first"
runtime_blob="$(git rev-parse HEAD:Sources/LunaHostCore/LunaFrameRuntime.swift)"
renderer_blob="$(git rev-parse HEAD:Sources/LunaUITestApp/DemoSharedRenderer.swift)"
[[ "$runtime_blob" == "$expected_runtime_blob" ]] || fail "unexpected LunaFrameRuntime.swift baseline blob: $runtime_blob"
[[ "$renderer_blob" == "$expected_renderer_blob" ]] || fail "unexpected DemoSharedRenderer.swift baseline blob: $renderer_blob"
python3 scripts/apply-exact-unified-diff.py --repo-root "$repo_root" --patch "$patch_file"
./scripts/verify-c2.5d2r2-working-tree.sh
printf '\n%s\n' 'Luna C2.5D2R2 source patch applied and verified in the working tree.'
printf '%s\n' 'Run the focused tests, full validation, and native acceptance before staging.'
