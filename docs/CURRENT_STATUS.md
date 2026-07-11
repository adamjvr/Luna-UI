# Current Luna UI Status

This document is the working checkpoint after Phase 5D.2 new-file lifecycle proof.

---

## Current Checkpoint

Luna UI is through **Phase 5D.2**.

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
- logical-line scroll state, visible line ranges, content height, scrollbar/minimap-lane placeholder geometry, scrolled hit testing, and accessibility visible text range metadata;
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
- a split demo harness with editor mode as the default Moth-like performance baseline, proof-gallery mode for earlier visual/stress proofs, pointer-motion coalescing at the host boundary, state-change-based pointer invalidation, quiet command logging by default, input coalescing diagnostics, and proof-era surfaces removed from the default hot path;
- targeted tab/document close routing that keeps the command product-neutral while carrying a clicked/right-clicked target document through `LunaCommandContext`, reuses dirty-close policy for tab close buttons and tab context menus, and synchronizes document/workspace/shell state after closing a clean document;
- repository-wide MPL-2.0 license migration with `LICENSE` updated to the Mozilla Public License 2.0, concise SPDX headers added to package/source/test/shim/module-map files, and project documentation aligned around the new license;
- a Phase 5D local file I/O proof in the demo app, with `--open` launch paths, real UTF-8 reads, local saves/save-all, local files projected under a `Local Files` sidebar root, and filesystem errors surfaced as status messages while LunaUI remains product-neutral;
- a Phase 5D.1 checked-in public-domain demo corpus under `Examples/PublicDomainDemoFiles`, manifest verification tooling, launch helpers, and `--open-demo-corpus` selection flags for repeatable real-file editor demos;
- a Phase 5D.2 new-file lifecycle proof with Ctrl+N/File > New File untitled buffers, `--new-untitled`, safe `--create` empty-file launch support, demo Save As routing, and no-overwrite filesystem behavior owned by `LunaUITestApp`.

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

---

## What Is Not Built Yet

Luna does not yet have:

- minimap rendering;
- real project/document/tab persistence;
- native open/save panels and product save-location prompts;
- real dirty-document save/discard/cancel prompt UI;
- tab overflow, pinned-tab refinement, and split/pane groundwork;
- the actual Moth Text application target.

---

## Immediate Next Implementation Target

```text
Phase 5E — Tab Overflow and Split/Panes
```

Phase 5D.2 is complete. Phase 5E should build on the now-responsive, file-backed, repeatably demoable editor harness by improving editor-shell behavior for more realistic tab pressure: overflow behavior when tabs exceed strip width, pinned-tab layout refinement, and early split/pane groundwork without turning Luna into Moth Text.
