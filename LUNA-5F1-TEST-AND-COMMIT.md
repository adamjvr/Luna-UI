# Luna UI Phase 5F.1 — Test, Run, and Commit

This overlay is for the existing Luna-UI Git repository. It contains no `.git`
directory and must be committed only after the independent Luna validation passes.

## Build and test

```bash
cd ~/GitHub/Luna-UI
swift package clean
swift build
swift test
```

## Run the graphical proof

```bash
swift run LunaUITestApp
```

Confirm the window opens, the editor harness renders, pane focus changes when the
pane proof is clicked, the divider responds, and the application closes cleanly.

## Commit and push Luna only

```bash
git status --short
git add -A
git diff --cached --check
git diff --cached --stat

git commit \
  -m "feat(workspace): add Luna Phase 5F.1 pane and tab mechanics" \
  -m "Introduce product-neutral split-pane trees, active-pane routing, directional focus traversal, divider resizing, command-context projection, pinned tabs, and deterministic tab overflow." \
  -m "Add reusable tests, demo proof, and an application-owned termination veto while preserving application ownership of documents, views, and pane meaning."

git push origin main
```

Only after this push succeeds should Moth Text run `./scripts/update-luna.sh`.
