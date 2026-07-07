# Luna UI Roadmap

Luna UI is the Swift-native application engine underneath Moth Text. The goal is not to build a thin wrapper around AppKit, SwiftUI, GTK, Qt, Electron, or any web stack. The goal is to own the editor-facing UI stack from input through layout, paint, rendering, accessibility, and platform hosting.

This roadmap merges the original Luna UI plan with the HybX / Hybrid RobotiX architecture pass. The original Luna goals remain intact: custom rendering, text shaping, GPU rendering with CPU fallback, cross-platform parity, Sublime-style theming compatibility, and a public reusable API. The HybX influence adds a stronger semantic runtime spine: accessibility from day one, typed commands, widget identity, modal overlays, live announcements, and a hard boundary between app policy and platform glue.

Hybrid RobotiX / HybX is credited as an architectural influence. Luna does not vendor or port HybX Rust code. See: <https://codeberg.org/hybridrobotix>

---

## Product Definition

Luna UI is:

- a from-scratch UI and rendering engine written in Swift;
- a reusable engine, not the Moth Text application itself;
- cross-platform by design, with macOS and Linux as first-class targets;
- custom-drawn and editor-first;
- accessibility-first, command-driven, and semantically structured;
- renderer-backend independent, with CPU as correctness reference and GPU as production direction.

Luna UI is not:

- a SwiftUI app;
- an AppKit clone;
- a GTK/Qt/Electron wrapper;
- a general-purpose consumer UI toolkit;
- a place for Moth-specific editor policy.

---

## Architectural Doctrine

The most important rule:

> If Luna can draw a widget, Luna must also be able to describe it semantically.

That means every real widget must eventually participate in all of these systems:

- stable identity;
- explicit bounds;
- layout;
- display list generation;
- hit testing;
- focus behavior;
- command/action behavior where appropriate;
- accessibility node generation;
- accessibility children;
- live announcement behavior where appropriate.

This prevents the classic custom-UI failure where the visible UI, clickable UI, and screen-reader UI become three separate inconsistent worlds.

---

## Merged Module Model

The intended long-term module map is:

```text
LunaCore
  Shared primitive types, stable node IDs, geometry, diagnostics.

LunaAccessibility
  Pure Swift accessibility model: roles, actions, text ranges, trees, live regions.

LunaCommands
  Command IDs, key equivalents, descriptors, command registry.

LunaText
  Font lookup, shaping, ligatures, bidi, combining marks, glyph runs, metrics.

LunaRender
  Backend-independent display lists, CPU renderer, framebuffer contract, GPU path.

LunaTheme
  Theme tokens, colors, metrics, contrast-aware palettes, Sublime color scheme import later.

LunaHostCore
  Platform-neutral window/input/timing/clipboard/accessibility host contracts.

LunaHostSDL
  SDL-backed Linux/macOS host boundary. SDL imports stay here.

LunaHostMetal
  macOS Metal renderer/host path. Metal imports stay here.

LunaUI
  Widgets, layout, focus, overlays, menus, prompts, status bars, UI context.

LunaUITestApp
  Proof application only. It exercises Luna, but does not become the engine.
```

Boundary rule:

```text
Only host/platform targets may import OS or C platform APIs.
Only render targets may own renderer backend details.
Only accessibility bridge targets may translate to platform accessibility APIs.
App/demo/editor code talks to Luna through typed Swift APIs.
```

---

## Current Checkpoint

The current architecture starter has established:

- `LunaCore` for node identity, geometry, and diagnostics;
- `LunaAccessibility` for semantic nodes, roles, actions, text ranges, and live announcements;
- `LunaCommands` for typed command IDs and command descriptors;
- expanded `LunaUI` contracts for metrics, widgets, modal requests, and UI context;
- Linux SDL2 build fixes for Swift 6.2;
- the CPU demo running on Pop!_OS / Linux;
- the framebuffer/text coordinate bug fixed so the demo renders text correctly;
- README credit for HybX / Hybrid RobotiX.

This is the first staged architecture cut. It is not the complete Luna rewrite.

---

## Phase 0 — Architecture Spine Bootstrap

Status: started.

Purpose: establish the semantic runtime spine without deleting existing Luna functionality.

Deliverables:

- `LunaCore` primitive values and stable IDs;
- `LunaAccessibility` pure Swift semantic tree;
- `LunaCommands` typed command descriptors;
- `LunaUIContext` as the app/runtime boundary;
- `LunaWidget` contract tying together draw, hit-test, and accessibility;
- modal request types for prompt/list/confirm/notice/completion UI;
- architecture tests for the pure Swift layers;
- Linux SwiftPM/SDL2 package hygiene.

Exit criteria:

- `swift build` succeeds on Linux;
- `swift test` succeeds for architecture tests;
- the CPU demo runs;
- the codebase clearly states that accessibility and commands are core infrastructure, not later Moth features.

---

## Phase 1 — Real Widget Through the Full Contract

Status: implemented as the first proof slice.

Purpose: prove the new spine is actually becoming Luna, not sitting beside Luna.

Build one real widget, implemented as `LunaSemanticActionWidget`, that uses:

- `LunaNodeID`;
- explicit `LunaRect` bounds;
- display list output;
- hit testing;
- theme tokens;
- accessibility node output;
- optional command trigger;
- `LunaUIContext.announce()`;
- `LunaUIContext.requestRefresh()`.

Exit criteria:

- `LunaSemanticActionWidget` appears in `LunaUITestApp` as a rendered Phase 1 proof panel;
- it can be hit-tested;
- it exposes a semantic accessibility node;
- a command/action path is exercised in `LunaUIPhase1Tests`;
- the same widget state drives rendering, interaction, and accessibility.

---

## Phase 1B — Live Pointer Routing Proof

Status: implemented as the live demo interaction slice.

Purpose: prove that host mouse input can enter Luna through a platform-neutral event path and activate the same semantic widget used for rendering and accessibility.

Deliverables:

- `LunaPointerEvent`, `LunaPointerButton`, and `LunaPointerPhase`;
- `LunaPointerActivationResult`;
- `LunaActionableWidget.handlePointerEvent(...)`;
- SDL mouse button translation in `LunaUITestApp`;
- demo status text showing hit/miss/command results;
- tests proving inside clicks activate, outside clicks miss, and non-primary buttons do not activate.

Exit criteria:

- clicking the Phase 1B panel in the Linux SDL demo queues `luna.demo.phase1`;
- a visible count/status update appears in the demo;
- the terminal logs the requested command;
- pure Swift tests cover the platform-neutral pointer routing path.

---

## Phase 2 — UI Runtime, Focus, and Overlay Manager

Purpose: create the reusable app runtime services Moth will need.

Deliverables:

- focus model;
- hovered node vs keyboard focus vs accessibility focus separation;
- overlay/modal coordinator;
- prompt overlay;
- list/quick-panel overlay;
- confirmation dialog;
- notice/toast;
- completion popup shell;
- live announcement queue;
- basic menu model.

Exit criteria:

- overlays are not ad-hoc demo widgets;
- modal input routing is explicit;
- accessibility tree updates include modal content;
- command palette and completion UI can later be implemented using the same primitives.

---

## Phase 3 — Accessible Text View Prototype

Purpose: establish the editor-facing text control Luna provides to Moth.

Deliverables:

- text view widget with semantic identity;
- caret and selection rendering;
- keyboard text input;
- mouse selection;
- copy/paste through host abstraction;
- scroll model;
- line/column status hooks;
- text range accessibility;
- live announcements for caret movement and selection changes.

Important constraint:

This does not yet need to be the final Moth text buffer. It can be a proof widget, but it must use the right accessibility and rendering contracts.

Exit criteria:

- one editable text view runs in the test app;
- screen-reader semantics can be represented in Luna's pure Swift tree;
- caret, selection, and displayed text use the same coordinate convention;
- no app code imports SDL/AppKit/Metal to make text editing work.

---

## Phase 4 — Renderer Consolidation and Snapshot Tests

Purpose: lock down the rendering contract before the renderer grows.

Deliverables:

- documented framebuffer coordinate convention;
- display list snapshot tests;
- CPU renderer golden tests;
- text orientation regression test for the previous mirrored-text bug;
- dirty-rect / damage-region model draft;
- renderer debug overlays for bounds, glyphs, and dirty regions.

Rules:

- CPU renderer is the correctness reference.
- GPU renderers must match the CPU output within defined tolerances.
- Coordinate conventions must be documented and tested.

Exit criteria:

- rendering regressions like mirrored text are caught automatically;
- display list output can be tested without launching a window;
- renderer code remains backend-independent above the backend boundary.

---

## Phase 5 — Theme System and Sublime Color Scheme Import

Purpose: preserve the original Luna/Moth requirement that Sublime-style theming compatibility is a first-class goal.

Deliverables:

- `LunaTheme` token model;
- editor color roles;
- chrome color roles;
- status/menu/overlay color roles;
- contrast-aware built-in palettes;
- theme picker API shape;
- `.sublime-color-scheme` importer starter;
- theme snapshot fixtures.

Exit criteria:

- widgets consume tokens instead of hardcoded colors;
- test app can switch themes;
- imported Sublime-style colors can map into Luna tokens without making the Luna core internally depend on Sublime file formats.

---

## Phase 6 — Host Boundary Cleanup

Purpose: seal platform-specific imports below Luna host targets.

Deliverables:

- SDL window/event loop owned by `LunaHostSDL`;
- Metal/AppKit details owned by macOS host/render targets;
- platform clipboard contract;
- platform timer/display-link contract;
- platform accessibility bridge contract;
- test app no longer directly imports SDL.

Exit criteria:

- `LunaUITestApp` imports Luna targets only;
- platform C APIs stay below host boundaries;
- Moth Text will never need to import SDL, AppKit, GTK, or Metal directly to run normal editor UI.

---

## Phase 7 — GPU Path and Backend Switching

Purpose: fulfill the original GPU-default, CPU-fallback renderer goal.

Deliverables:

- backend-independent display list stays stable;
- CPU renderer remains reference backend;
- Metal backend path on macOS;
- Linux GPU backend research path, likely Vulkan or another explicit GPU layer later;
- runtime renderer selection;
- renderer parity tests.

Exit criteria:

- same UI can render through CPU and GPU paths;
- CPU fallback remains useful for debugging, CI, and correctness;
- platform backend details do not leak into widgets or app code.

---

## Phase 8 — Public API Stabilization

Purpose: make Luna reusable, not just an internal Moth engine.

Deliverables:

- documented public entry points;
- stable naming conventions;
- examples for embedding a Luna app;
- versioned API surface for core primitives;
- test app upgraded into a meaningful sample;
- docs for architecture, theming, rendering, accessibility, and host layers.

Exit criteria:

- a non-Moth Luna sample app can be written without touching renderer internals;
- downstream apps consume Luna through clean Swift APIs;
- the engine/app boundary is clear.

---

## Long-Term Luna UI Success Criteria

Luna UI is successful when:

- it can host Moth Text without native UI widgets;
- rendering is deterministic and tested;
- complex text shaping is correct from day one;
- accessibility is not a retrofit;
- the same widgets drive display, hit-testing, and semantic output;
- Linux and macOS behavior remain intentionally aligned;
- Moth Text can focus on editor behavior instead of platform or UI infrastructure.
