# Current Luna UI Status

This document is the working checkpoint after Phase 3B caret and static selection work.

---

## Current Checkpoint

Luna UI is through **Phase 3B**.

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
- non-editable caret geometry, static selection rectangles, text-coordinate hit testing, and accessibility caret/selection metadata.

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
1 = Luna demo blue
2 = demo-only Moth Obsidian
3 = high-contrast proof
```

The Moth Obsidian demo palette is:

```text
window/background black  #070709
button/control graphite  #131416
dark gray layer          #242426
light gray text          #888991
text highlight blue      #003CFF
```

The blue highlight should stay mostly out of sight until text selection, focused fields, selected rows, or caret/focus behaviors exist.

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

---

## What Is Not Built Yet

Luna does not yet have:

- editable text input;
- scrolling text viewport;
- command palette / quick panel;
- find/replace panel;
- menu bar and dropdown menus;
- tabs, sidebar, status bar, or minimap;
- the actual Moth Text application target.

---

## Immediate Next Implementation Target

```text
Phase 3C — Text View Scroll and Viewport
```

Phase 3C should add scroll offset, visible range control, content height, and hit testing with scroll offset on top of the Phase 3B caret/selection geometry. It should still avoid full editable input until the viewport model is correct.
