# Current Luna UI Status

This document is the working checkpoint for Convergence C2.4 interactive runtime and presentation scheduling after C2.3 failed graphical responsiveness acceptance.

---

## Current Checkpoint

Luna UI is through **Convergence C2.4** on the paired Moth track. C2.2 fixed exact text geometry and scrolling. C2.3 restored the kitchen-sink demo and added useful diagnostics, but its stateless polling/presentation coupling failed native graphical acceptance. C2.4 replaces it with persistent semantic scheduling and presentation deadlines independent from raw acquisition limits.

The newest paired-application contracts are:

- Phase 5E.1 public SDL application lifecycle, now including an application-owned termination veto for unsaved-document workflows;
- Phase 5E.2 immutable text-storage snapshots, independent document-view presentation state, revision invalidation, and injected find sessions;
- Phase 5F.1 recursive pane trees, horizontal/vertical split geometry, active-pane state, visual and wrapping traversal, divider resizing, neutral pane command context, pinned tabs, deterministic tab overflow, and reusable overflow state;
- Phase 5F.2A pane content frames and pane-bound text surfaces with independent clipping, width-correct soft wrapping, wrapped visual-row scrolling, UTF-8-safe geometry, and reflow after divider/window changes;
- Convergence C1A platform-neutral cursor intent, SDL system-cursor caching, native pointer capture, persistent product-neutral pane hover/drag state, and forgiving divider controls;
- Convergence C1B reusable text-selection interaction state for click/Shift-click/drag, Unicode-aware word/logical-line ranges, captured gesture cancellation, wrapped-row tracking, and edge autoscroll;
- Convergence C2 boundary validation: Moth implements document-owned history, grouping, inverse replay, multi-view restoration, and saved checkpoints;
- Convergence C2.1 `LunaTextRender`: HarfBuzz UTF-8 shaping, FreeType glyph masks, cached CPU framebuffer painting, explicit missing-glyph boxes, monospaced font discovery, and cluster/advance data for editor geometry;
- Stabilization S1 Ubuntu CI, native-dependency verification, full SwiftPM build/test validation, and monthly GitHub Actions dependency maintenance;
- M2.2B1 searchable disabled quick-panel items, preserving disabled presentation and accessibility metadata while allowing product-owned availability reasons;
- Convergence C2.2 shaped-row geometry with UTF-8 insertion boundaries and 26.6 positions, exact soft-wrap/caret/selection/hit-test convergence, platform-neutral scroll events, SDL wheel and trackpad translation, precise-delta accumulation, scrollbar paging, and thumb dragging;
- Convergence C2.3 demo restoration, 340-row scroll corpus, committed-text authority, and latency diagnostics retained; its raw-batch presentation policy is documented as rejected;
- Convergence C2.4 persistent cross-pass semantic scheduling, pointer/text coalescing, click/command ordering barriers, idle/threshold/deadline text dispatch, and raw-acquisition limits that never define frame boundaries;
- a `LunaTheme` public product so downstream applications can own their palettes without copying Luna internals.

The engine now has:

- a Swift package module spine for core types, commands, accessibility, input, layout, text, rendering, themes, host bridges, UI widgets, and the test app;
- a semantic widget contract where drawing, hit testing, accessibility, and command activation come from the same state;
- live pointer routing into the semantic widget;
- modal overlay infrastructure with notice, prompt, list, confirm, and completion shells;
- modal interaction polish for hover, press, focus/default, cancel, Enter, Space, Escape, and Tab behavior;
- platform-neutral host input events with SDL translation contained under `LunaHostSDL`;
- layout and resize reflow through `LunaLayout`;
- modal text reflow and clipping;
- shared bounded text behavior for labels, modal text, prompt fields, status text, and future controls;
- responsive modal control layout for narrow viewports;
- product-neutral visual theme tokens and render-ready style snapshots;
- demo theme switching for Luna demo blue, demo-only Moth Obsidian, and high-contrast proof;
- a renderer color contract so logical RGBA hex colors display correctly through the framebuffer and SDL presenter;
- a static accessible text-view primitive with line/gutter layout, theme-driven paint geometry, visible line text ranges, hit testing, and accessibility children;
- non-editable caret geometry, static selection rectangles, text-coordinate hit testing, and accessibility caret/selection metadata;
- logical-line and wrapped visual-row scroll state, visible line ranges, content height, wheel/trackpad requests, fractional precise-delta accumulation, interactive scrollbar paging/thumb dragging, scrolled hit testing, and accessibility visible text range metadata;
- a small editable text document/state layer with insertion, newline, backspace/delete, selection replacement, caret movement, host text-input events, and editable accessibility metadata;
- a command palette / quick-panel foundation with filtering, keyboard navigation, command activation, theme-driven rows, pointer selection, and accessibility nodes;
- a cleaned-up `LunaUITestApp` layout with a readable header, main editor area, side proof panel, and bottom status bar so phase/debug information no longer stacks over the editor;
- a generic find / replace foundation with product-neutral query/options/results, literal and regex scanning, whole-word/case toggles, text-view match highlights, replace-current/replace-all operations, keyboard/pointer interaction, theme-driven panel visuals, and accessibility nodes;
- completed interactive user text selection with click-drag selection, Shift-click/Shift-arrow extension, selection replacement/delete behavior, and pointer modifier propagation through LunaInput;
- command-palette-only demo theme switching so bare `1`, `2`, and `3` can be typed into the editor as text;
- Select All through both `Ctrl+A` and the command palette, backed by a product-neutral editable text selection primitive;
- tightened active overlay/input ownership so palette and find-panel keyboard events do not leak into the editor underneath;
- a product-neutral menu bar/dropdown foundation with top-level menus, dropdown rows, separators, disabled items, checked items, shortcut display, first-pass submenus, pointer activation, keyboard navigation, theme-driven visible menu labels/shortcuts/checkmarks, accessibility menu/menuitem nodes, and demo command dispatch;
- a product-neutral editor shell foundation with reusable tab strip, sidebar tree/list rows, editor content frame, status-bar segments, pointer interaction, theme-driven geometry, visible demo labels, accessibility nodes, and demo integration that frames the editable text view;
- a product-neutral context menu foundation with secondary-click floating menu presentation, reusable Luna menu items/dropdown rows, editor/tab/sidebar/status demo contexts, separators, disabled items, checked items, shortcut display, first-pass submenus, pointer and keyboard routing, theme-driven visible labels, accessibility menu/menuitem nodes, and demo command dispatch;
- a product-neutral anchored completion popup foundation with app-supplied completion items, caret/anchor positioning, viewport clamping, selected rows, completion details, keyboard and pointer activation, insertion/command result payloads, theme-driven geometry, visible demo labels/details, and accessibility list/list-item nodes;
- a product-neutral document/buffer identity layer with document descriptors, open-buffer storage, active-document routing, per-document caret/selection/scroll state, dirty tracking from editable text revisions, shell-tab projection, and demo tabs that switch the actual editable buffer;
- a product-neutral command runtime with dynamic command availability, checked/disabled/visible state, key binding matching, surface projection, handler execution against a mutable host, keyboard shortcut routing, and demo menu/palette/context/keymap dispatch through one command path;
- a product-neutral file/project adapter boundary with file/project IDs, file descriptors, project tree snapshots, workspace state, sidebar projection helpers, open/save request/result contracts, dirty-document close policy, and an in-memory demo workspace adapter that opens and saves document buffers without baking real Moth filesystem policy into Luna;
- a host-runtime frame pacing/invalidation foundation with `LunaFrameTimingSample`, `LunaFrameTimingStats`, `LunaInvalidationReason`, `LunaFrameInvalidationSet`, `LunaFrameRequest`, `LunaFramePacer`, `LunaRuntimeTick`, SDL vsync/delay cleanup, and demo status-bar diagnostics for frame timing and invalidation reasons;
- a three-mode demo harness with the complete kitchen-sink presentation as the default, explicit `--editor` performance mode, retained proof-gallery compatibility mode, pointer-motion and committed-text coalescing at the host boundary, bounded polling, state-change-based invalidation, quiet command logging by default, and input/latency diagnostics;
- targeted tab/document close routing that keeps the command product-neutral while carrying a clicked/right-clicked target document through `LunaCommandContext`, reuses dirty-close policy for tab close buttons and tab context menus, and synchronizes document/workspace/shell state after closing a clean document;
- repository-wide MPL-2.0 license migration with `LICENSE` updated to the Mozilla Public License 2.0, concise SPDX headers added to package/source/test/shim/module-map files, and project documentation aligned around the new license;
- a Phase 5D local file I/O proof in the demo app, with `--open` launch paths, real UTF-8 reads, local saves/save-all, local files projected under a `Local Files` sidebar root, and filesystem errors surfaced as status messages while LunaUI remains product-neutral;
- a Phase 5D.1 checked-in public-domain demo corpus under `Examples/PublicDomainDemoFiles`, manifest verification tooling, launch helpers, and `--open-demo-corpus` selection flags for repeatable real-file editor demos;
- a Phase 5D.2 new-file lifecycle proof with Ctrl+N/File > New File untitled buffers, `--new-untitled`, safe `--create` empty-file launch support, demo Save As routing, and no-overwrite filesystem behavior owned by `LunaUITestApp`;
- a Phase 5D.3 host dialog boundary with LunaHostCore dialog request/result types, injectable scripted dialog service, interactive `Open…`, `Save As…`, Save-on-untitled, and dirty-close Save / Don’t Save / Cancel routing in the demo app, plus Linux/macOS desktop-helper bridges outside LunaUI;
- a Phase 5D.3.1 proof-gallery animation pacing cleanup with a host-runtime animation clock, clamped logical deltas after stalls/dialogs/debugger pauses, animation invalidation diagnostics, and duplicate demo-chrome drawing removed from the shared renderer;
- a Phase 5D.3.2 proof-gallery frame-cache optimization where animation-only frames restore a cached static proof frame, redraw only dynamic proof surfaces, copy framebuffer pixels explicitly, and avoid presenter-path reflection during continuous animation uploads.

---

## License Status

Phase 5C.2.2 migrates Luna-UI from the previous permissive license file to `MPL-2.0`. The full license text is in `LICENSE`; source, test, package-manifest, C shim, and module-map files now carry concise SPDX license identifiers. Documentation should refer to the project license as `MPL-2.0`.

## Current Hard Rules

```text
draw bounds = hit-test bounds = accessibility bounds
```

```text
text-bearing widgets never draw as if they have infinite width
```

```text
controls choose sane bounds before text is laid out inside them
```

```text
Luna library APIs stay product-neutral
```

```text
product-specific palettes belong in applications or demo fixtures
```

```text
hex parsing is not theming unless the renderer preserves color channels
```

---

## Product Boundary

Luna UI is the reusable engine. It can render any application-supplied color scheme.

Moth Text is one future application built on Luna. Its obsidian/graphite palette is currently demonstrated inside `LunaUITestApp` only so the engine can prove consumer-supplied themes work.

Moth names should not appear in Luna library public APIs. Moth names are acceptable in:

- `LunaUITestApp` demo fixtures;
- Moth Text product code later;
- docs that explain the engine/product split.

---

## Demo Theme Status

`LunaUITestApp` currently proves three theme paths:

```text
Ctrl+P -> Theme: Luna Demo Blue
Ctrl+P -> Theme: Moth Obsidian Demo
Ctrl+P -> Theme: High Contrast Proof
```

The Moth Obsidian demo palette is:

```text
window/background black  #070709
button/control graphite  #131416
dark gray layer          #242426
light gray text          #888991
text highlight blue      #003CFF
```

The blue highlight is now visible for real user text selection, focused fields, selected rows, and caret/focus behaviors. It should not be used as a broad panel/control fill.

---

## What Is Complete

- Phase 0 — Architecture baseline: complete.
- Phase 1A — Semantic widget proof: complete.
- Phase 1B — Pointer routing: complete.
- Phase 2A — Modal overlay runtime: complete.
- Phase 2B — Modal interaction polish: complete.
- Phase 2C — Host boundary and theme customization cleanup: complete.
- Phase 2D — Layout, resize, and accessibility reflow: complete.
- Phase 2D.1 — Modal text reflow and clipping: complete.
- Phase 2D.2 — Universal bounded text and control reflow: complete.
- Phase 2D.3 — Responsive modal control layout: complete.
- Phase 2E — Visual style token lockdown: complete.
- Phase 2E.1 — Product-neutral theme API cleanup: complete.
- Phase 2E.2 — Renderer color contract and demo palette proof: complete.
- Phase 3A — Static Accessible Text View: complete.
- Phase 3B — Caret Geometry and Static Selection Model: complete.
- Phase 3C — Text View Scroll and Viewport: complete.
- Phase 3D — Editable Text Input Foundation: complete.
- Phase 4A — Command Palette / Quick Panel: complete.
- Phase 4A.1 — LunaUITestApp Demo Layout Cleanup: complete.
- Phase 4B — Generic Find / Replace Panel Foundation: complete.
- Phase 4B.1 — Interactive Text Selection Completion: complete.
- Phase 4B.2 — Demo Command Routing and Text Input Focus Cleanup: complete.
- Phase 4C — Menu Bar and Dropdown Menus: complete.
- Phase 4D — Tabs / Sidebar / Status Bar Shell: complete.
- Phase 4E — Context Menu: complete.
- Phase 4F — Completion Popup: complete.
- Phase 5A — Real Document / Buffer Integration: complete.
- Phase 5B — Product-Neutral Editor Command Runtime: complete.
- Phase 5C — File / Project Adapter Boundary: complete.
- Phase 5C.1 — Frame Pacing, Invalidation, and Runtime Boundary: complete.
- Phase 5C.2 — Editor Harness Split and Input Coalescing: complete.
- Phase 5C.2.1 — Targeted Tab / Document Close Routing: complete.
- Phase 5C.2.2 — MPL-2.0 License Migration: complete.
- Phase 5D — Real File I/O Proof: complete.
- Phase 5D.1 — Public-Domain Demo Corpus Integration: complete.
- Phase 5D.2 — New File / Untitled Buffer / Save As Proof: complete.
- Phase 5D.3 — Host Dialog Boundary for Native Open / Save / Dirty Close: complete.
- Phase 5D.3.1 — Proof Gallery Animation Pacing: complete.
- Phase 5D.3.2 — Proof Gallery Static Frame Cache: complete.
- Convergence C1A/C1B — Pointer, cursor, divider, and selection convergence: complete.
- Convergence C2 — Moth-owned history boundary validation: complete.
- Convergence C2.1 — Shaped Unicode framebuffer rendering: complete and graphically validated.
- Stabilization S1 — Ubuntu CI and reproducible repository validation: complete.
- M2.2B1 — Searchable disabled quick-panel command presentation: implemented in this revision.

---

## What Is Not Built Yet

Luna does not yet have:

- minimap rendering;
- real project/document/tab persistence;
- first-class portal/Win32/AppKit dialog providers beyond the current demo helper bridge;
- native open/save panels inside LunaUI itself, which remains intentionally out of scope;
- final physical SwiftPM target cuts for optional document/editor component libraries;
- visible split-command chrome and full keyboard shortcut routing for pane operations;
- a polished tab-overflow popup/list presentation beyond the reusable overflow state and geometry;
- application-owned editor groups, cloned views, project persistence, and session persistence;
- the actual Moth Text application target, which remains a separate repository by design.

---

## Immediate Next Implementation Target

```text
A1 — paired Luna/Moth architecture and quality audit
```

C2.4 must first pass native interaction acceptance: clicks, menus, commands,
navigation, text input, scrolling, resizing, and dialogs must react promptly with
no growing backlog. After both repositories are committed, the next work is an
audit of runtime ownership, Swift/API quality, tests, documentation, and measured
performance debt. M3A real tabs begins only after that audit is reviewed.

---

## Phase 5E.1 — Reusable SDL Application Host

Phase 5E.1 extracts the Linux SDL lifecycle from `LunaUITestApp` into the
public `LunaHostSDL` package product.

The reusable host now owns:

- SDL initialization and shutdown;
- native window creation and destruction;
- normalized Luna input polling and coalescing;
- framebuffer creation and resize handling;
- invalidation-driven frame scheduling;
- CPU framebuffer presentation;
- frame timing diagnostics;
- event-loop lifetime through window close.

Applications provide a `LunaSDLApplicationScene` and remain independent of raw
SDL APIs. `LunaUITestApp` now uses this same public path, ensuring that the
framework demo and downstream consumers exercise one host implementation.

This is the first concrete Phase 5E extraction seam and enables Moth Text M0.2
to open a real Luna-rendered Linux application window.

---

## Phase 5E.2 — Document/View Adapter Seams

**Status: complete in this revision.**

Phase 5E.2 adds the product-neutral boundary needed for downstream editors to
share one authoritative document across independent presentations without
turning Luna's proof text model into a product source buffer.

Delivered:

- `LunaTextStorageAdapter` and immutable `LunaTextStorageSnapshot` values;
- typed absolute UTF-8 storage ranges and monotonic content revisions;
- independent `LunaDocumentViewPresentationState` values with view identity,
  caret, selection, preferred column, scroll state, and observed revision;
- per-view revision invalidation and coordinate clamping after shared content
  changes;
- injected `LunaFindResultsProviding` and `LunaFindPanelSession` contracts so
  scanning, replacement, transaction, and undo policy can stay application-owned;
- a public CPU debug bitmap-text renderer for downstream graphical bring-up;
- regression tests proving one document can back two independent views.

`LunaEditableTextDocument` remains a small deterministic reusable proof model.
It is not the future Moth Text source buffer.


---

## Phase 5F.1 — Pane and Tab Mechanics

**Status: complete in this revision.**

Delivered:

- recursive `LunaPaneNode` trees with stable pane and split identities;
- horizontal and vertical split layout with bounded fractions and minimum pane extents;
- active-pane state, next/previous wrapping traversal, and visual directional traversal;
- split insertion, removal/collapse, and reusable divider interaction;
- neutral command-context projection carrying active and target pane IDs;
- pinned-tab compact geometry, active-tab visibility, hidden-tab reporting, and overflow-button state;
- regression tests proving Luna owns mechanics while applications own pane meaning;
- an SDL scene termination veto so applications can cancel native window close for unsaved documents.
