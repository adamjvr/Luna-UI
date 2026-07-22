# Luna UI and Moth Text Paired Iteration Protocol

This document defines the required development order for changes that affect both Luna UI and Moth Text.

## Governing Order

```text
Luna change
  -> build Luna
  -> test Luna
  -> commit and push Luna
  -> update Moth's Luna submodule pointer
  -> implement Moth integration
  -> build Moth
  -> test Moth
  -> commit and push Moth
```

Moth must never consume uncommitted Luna work. Every Moth revision records a specific committed Luna revision through `Dependencies/Luna-UI`.

## Luna Iteration

Before editing:

```bash
git status --short
```

After editing:

```bash
./scripts/validate-iteration.sh
```

The Luna commit must be created and pushed before Moth updates its submodule pointer. The Luna GitHub Actions `CI / Ubuntu SwiftPM validation` job must pass before that commit is treated as consumable by Moth.

## Moth Consumption

From the Moth repository:

```bash
cd Dependencies/Luna-UI
git switch main
git pull --ff-only
cd ../..

git submodule status
git diff --submodule=log -- Dependencies/Luna-UI
```

Moth integration then proceeds against that exact Luna commit.

## Delivery Isolation Law

Moth ZIPs and patches must not contain or modify:

```text
Dependencies/Luna-UI/**
Dependencies/Luna-UI/.git
```

A Moth overlay contains Moth-owned files only. The submodule pointer is updated by Git in the user's real Moth checkout, never by copying Luna files into an archive.

Use:

```bash
./scripts/package-overlay.sh <output.zip>
```

The packaging script rejects tracked changes below `Dependencies/Luna-UI` and excludes the entire dependency directory from the archive.

## Continuous Integration Gate

Both repositories carry Ubuntu workflows that reproduce their permanent validation scripts from clean checkouts. Moth checkout must initialize the recorded Luna submodule recursively and verify that its checkout exactly matches the committed gitlink. After the first green runs, protect `main` and require the named CI checks.

## Validation Before Moth Commit

```bash
./scripts/validate-paired-iteration.sh

git submodule status
git diff --submodule=log
git status --short
```

The Moth commit may stage the submodule gitlink itself:

```bash
git add Dependencies/Luna-UI
```

It must not stage files from inside the Luna repository.

## Failure Conditions

Do not commit the paired Moth change when:

- Luna contains uncommitted changes;
- the checked-out Luna revision differs from Moth's recorded gitlink unexpectedly;
- Luna has not been pushed;
- Luna build or tests fail;
- Moth build or tests fail;
- a generated Moth overlay contains `Dependencies/Luna-UI`;
- implementation code crosses the Luna/Moth ownership boundary merely to avoid a proper API.

## M2.2B1 Command Convergence

M2.2B1 primarily composes existing Luna command, menu, and quick-panel APIs with
Moth-owned command IDs and product policy. Integration exposed one reusable Luna
filtering defect: disabled quick-panel items vanished from nonempty searches.
Luna corrects that behavior and adds a focused Phase 4A regression before Moth
advances its submodule.

Acceptance order:

1. run Luna's complete build and test gate;
2. manually exercise LunaUITestApp menus, command palette, New File, and dirty-close paths;
3. commit and push Luna;
4. advance the Moth submodule;
5. run focused Moth command tests and complete paired validation;
6. graphically verify keyboard, menu, and palette equivalence in Moth.

That originally identified M2.2B2 as next; post-M2.2B1 graphical validation inserted C2.2 before feature expansion.


## C2.2 exact geometry and scrolling checkpoint

C2.2 is a Luna-first reusable correction. Commit and validate Luna's shaped-row
insertion geometry, platform-neutral scroll event, SDL wheel translation, and
static-text scrollbar interaction before Moth advances its gitlink.

Acceptance requires:

1. `swift test --filter LunaTextRenderTests`;
2. `swift test --filter LunaUIPhase5F2ATests`;
3. `swift test --filter LunaHostSDLApplicationTests` on Linux;
4. the complete `./scripts/validate-iteration.sh` gate;
5. graphical proof that a long rapidly typed line keeps the caret at the exact
   rendered insertion point;
6. wheel/trackpad scrolling, lane paging, and thumb dragging without cross-pane
   viewport mutation.

Moth then adopts the exact Luna revision, routes scroll input to the pane beneath
the pointer, preserves fractional deltas per view, paints the caret after glyphs,
and validates the complete paired suite. M3A document sheets and real tabs are the
next product slice; C2.2 does not claim multiple-document behavior.


## C2.3 input-to-pixel latency and demo-restoration checkpoint

C2.3 is Luna-first because event polling, committed-text coalescing, frame timing,
and the kitchen-sink demo are reusable host/demo responsibilities.

Luna acceptance:

```bash
swift build
swift test --filter LunaHostPhase5C1Tests
swift test --filter LunaHostSDLApplicationTests
swift test --filter LunaUIPhase5CTests
swift test
./scripts/validate-iteration.sh
git diff --check
```

Manual Luna acceptance uses both modes:

```bash
swift run LunaUITestApp
swift run LunaUITestApp --editor
```

The first command must show the complete kitchen-sink presentation, long scroll
corpus, diagnostics HUD, and animated square. The second must remain the lean
input/render performance harness.

After Luna is committed, Moth advances the gitlink and validates frame-fair text
input, ordered batching, cache diagnostics, and the complete paired suite. M3A
real document tabs remains the next product slice.


## C2.4 interactive runtime checkpoint

C2.3 failed native interaction acceptance because a raw polling limit became a
presentation boundary. C2.4 must therefore be committed Luna-first and validated
with the persistent scheduler before Moth advances its gitlink.

Luna gate:

```bash
swift build
swift test --filter LunaInteractiveRuntimeTests
swift test --filter LunaHostPhase5C1Tests
swift test --filter LunaHostSDLApplicationTests
swift test
./scripts/validate-iteration.sh
swift run LunaUITestApp
swift run LunaUITestApp --editor
git diff --check
```

Moth then advances the exact Luna commit, validates the dictionary-based layout-cache hit path without linear
ordering-array maintenance and complete paired suite, and performs native interaction acceptance.
After both repositories are accepted, stop for the A1 paired audit. Do not begin
M3A automatically.
