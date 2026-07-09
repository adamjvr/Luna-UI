# Current Luna UI Status

This document is the working checkpoint after Phase 4C menu bar and dropdown menus.

---

## Current Checkpoint

Luna UI is through **Phase 4C**.

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
- a product-neutral menu bar/dropdown foundation with top-level menus, dropdown rows, separators, disabled items, checked items, shortcut display, first-pass submenus, pointer activation, keyboard navigation, theme-driven visible menu labels/shortcuts/checkmarks, accessibility menu/menuitem nodes, and demo command dispatch.

---

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

---

## What Is Not Built Yet

Luna does not yet have:

- tabs, sidebar, status bar, or minimap;
- the actual Moth Text application target.

---

## Immediate Next Implementation Target

```text
Phase 4D — Tabs / Sidebar / Status Bar Shell
```

Phase 4D should add product-neutral editor shell primitives for tabs, sidebar, and status bar layout/state. Moth can later feed those primitives real project folders, dirty document state, syntax mode, cursor status, and document metadata without baking Moth product naming into Luna's library API.
