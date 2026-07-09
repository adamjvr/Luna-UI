# Luna UI

**Luna UI** is a from-scratch, cross-platform UI and rendering engine written in Swift. It is the foundational UI layer for **Moth Text**, a future Sublime-class text editor, but Luna is intentionally designed as a standalone reusable engine that can power other applications.

This repository is **not Moth Text**.

This repository is the engine.

Luna UI owns the reusable infrastructure that a serious custom editor needs: rendering, layout, text shaping, input routing, theming, widgets, accessibility semantics, commands, modal overlays, and platform hosting. Moth Text will sit above Luna and define the editor product behavior.

---

## Current Roadmap Documents

The project direction is split into two roadmap documents:

- [`docs/LUNA_UI_ROADMAP.md`](docs/LUNA_UI_ROADMAP.md) — engine/runtime roadmap for Luna UI.
- [`docs/MOTH_TEXT_ROADMAP.md`](docs/MOTH_TEXT_ROADMAP.md) — editor-product roadmap for Moth Text.

The short version:

```text
Luna UI   = reusable Swift UI/runtime/rendering/accessibility engine
Moth Text = Sublime-class editor product built on Luna UI
```

The roadmap is intentionally broken into implementation gates. Recent work showed that broad phases like “modal overlays” hide too much detail. The repo now tracks subphases such as pointer routing, modal interaction polish, host-boundary cleanup, theme customization, layout/reflow, and accessibility bounds validation.

---

## Why Luna UI Exists

Moth Text is not being built on top of SwiftUI, AppKit widgets, GTK, Qt, Electron, or a web stack. That decision is deliberate.

Existing UI frameworks break down at the exact points that matter for a serious editor:

- precise pixel control;
- deterministic layout and rendering;
- huge-document performance;
- custom cursor, selection, gutter, minimap, and overlay rendering;
- proper complex text shaping;
- ligatures, bidi text, combining marks, and font fallback;
- theme compatibility with editors like Sublime Text;
- cross-platform visual parity;
- accessibility that matches the custom UI instead of being bolted on later.

Rather than fight those frameworks, Luna owns the stack.

---

## Relationship to Moth Text

```text
Moth Text
  Editor application, documents, projects, commands, packages, Sublime compatibility.

Luna UI
  Reusable UI/runtime engine: widgets, overlays, focus, commands, accessibility.

Luna Render / Text / Theme / Host
  Rendering, shaping, styling, and platform-specific host bridges.
```

Moth Text defines **what** the editor does.

Luna UI defines **how** it is drawn, interacted with, hosted, themed, and exposed semantically.

This means Moth should not own the renderer, SDL/AppKit/Metal imports, accessibility bridge, generic overlays, command palette UI, completion popup UI, menus, or platform event loop. Those belong in Luna.

---

## Design Goals

### Pixel-Exact Rendering

If a rectangle is supposed to be 1px wide at `(x: 12, y: 7)`, that is where it is drawn. No hidden platform padding. No accidental layout drift. No uninspectable framework heuristics.

### Text Is First-Class

Luna is editor-first. Text shaping, glyph positioning, caret placement, selection geometry, line layout, and font metrics are core requirements, not later polish.

### Accessibility From Day One

A custom UI engine must not create a separate inaccessible reality. Luna's rule is:

> If Luna can draw a widget, Luna must also be able to describe it semantically.

Every serious widget should eventually provide stable identity, bounds, display output, hit testing, and accessibility output from the same underlying state.

The geometry law is:

```text
draw bounds = hit-test bounds = accessibility bounds
```

### Command-Driven UI

Commands are shared infrastructure. Menus, shortcuts, command palettes, accessibility actions, tests, and eventually plugins should be able to call the same typed command IDs.

### Theme-Driven Visuals

Widgets do not own permanent colors. Themes/styles own colors. Luna has hex-driven color primitives and a renderer color contract so any application can supply exact values for editor backgrounds, chrome, tabs, menus, buttons, overlays, selections, caret, minimap, scrollbars, and status UI.

Moth Text is one consumer of that system, not something baked into Luna's public API. Moth-specific palettes may appear in `LunaUITestApp` as demo fixtures, but Luna library targets must remain product-neutral.

### Cross-Platform Visual Parity

macOS and Linux are first-class targets. The goal is not “close enough.” The goal is same spacing, same theme interpretation, same rendering model, and predictable behavior.

### GPU-Accelerated, CPU-Capable

The CPU renderer is the correctness reference and debug backend. GPU backends are the long-term production path. Both should consume backend-independent display lists.

---

## Architecture Overview

Current and intended modules:

```text
LunaCore
  Stable IDs, geometry primitives, diagnostics.

LunaAccessibility
  Pure Swift accessibility nodes, roles, actions, text ranges, live announcements.

LunaCommands
  Typed command IDs, key equivalents, command descriptors, command registry.

LunaInput
  Platform-neutral pointer, keyboard, window, and host input events.

LunaTextCore
  Pure text/glyph data types that do not require system text-shaping libraries.

LunaText
  Font lookup, shaping, ligatures, bidi, combining marks, glyph runs, metrics.

LunaRender
  Display lists, CPU renderer, framebuffer contract, future GPU backends.

LunaTheme
  Color primitives, hex parsing, theme tokens, control styles, Sublime color scheme import later.

LunaHostCore
  Platform-neutral host contracts.

LunaHostSDL
  SDL-backed host boundary for Linux/macOS bring-up. SDL imports and SDL event normalization stay here.

LunaHostMetal
  macOS Metal path. Metal/AppKit details stay here.

LunaUI
  Widgets, layout, focus, overlays, menus, prompts, status bars, UI context.

LunaUITestApp
  Proof app only. It must exercise Luna through the same architecture that Moth Text will use.
```

Boundary rule:

> Platform code never leaks upward, renderer backend details never leak sideways, and Moth Text does not import platform UI APIs to draw normal editor UI.

---

## Visual Direction

Luna is reusable, but the default editor-facing controls are shaped by the needs of a Swift-native Sublime-class editor: compact, dark, keyboard-first, and precise.

The default visual language is:

- dark editor-first interface;
- charcoal chrome, menus, panels, and overlays;
- blue-gray editor/content regions where the theme chooses that look;
- compact rectangular controls;
- thin borders and restrained contrast;
- subtle cyan/teal hover and selection accents;
- compact tabs, menus, quick panels, find panels, and status bars;
- no mobile-style bubbly controls;
- no Electron/VS Code/JetBrains default aesthetic.

Menu dropdowns are the main area where an editor built on Luna can innovate beyond strict visual mimicry. The behavior should preserve Sublime-like command coverage while allowing better command discovery, descriptions, search, and accessibility.

The Luna library should expose neutral theme/style tokens. Product names and exact product palettes belong in applications or demo fixtures, not in reusable Luna API names.

---

## HybX / Hybrid RobotiX Credit

The current Luna architecture cut is influenced by ideas mined from **HybX / Hybrid RobotiX**, especially the accessibility-first custom UI direction in the HybX Functional Code Editor work.

- Hybrid RobotiX / HybX: <https://codeberg.org/hybridrobotix>

Luna does **not** vendor or port HybX Rust code. The influence is architectural:

- accessibility as part of the widget contract;
- commands as shared infrastructure for menus, shortcuts, palettes, tests, and apps;
- modal overlays and UI context as runtime services;
- separation between app policy, UI runtime, renderer, and platform host;
- visible UI, hit testing, and semantic accessibility all derived from the same widget state.

Luna remains a Swift-native engine with its own implementation, renderer, text stack, theme system, and platform hosts.

---

## Build & Run

Luna UI builds as a Swift Package.

On Ubuntu / Pop!_OS:

```bash
sudo apt update
sudo apt install libharfbuzz-dev libfreetype6-dev libsdl2-dev pkg-config
```

Build:

```bash
swift build
```

Run tests:

```bash
swift test
```

Run the current CPU demo app:

```bash
swift run LunaUITestApp
```

On current Linux SwiftPM, SDL2 may emit warnings about filtered `-D_REENTRANT` flags. Those warnings are expected and do not indicate a failed build.

---

## Current State

The current checkpoint has:

- initial architecture spine: `LunaCore`, `LunaAccessibility`, `LunaCommands`, and expanded `LunaUI` contracts;
- existing renderer/text/theme/host goals preserved;
- Linux SDL2 package wiring fixed;
- Swift 6.2 Linux SDL enum and stderr issues fixed;
- CPU demo running on Linux;
- demo coordinate/text mirroring bug fixed;
- Phase 1A semantic widget proof implemented;
- Phase 1B live mouse-click routing into the semantic widget implemented;
- Phase 2A modal/overlay runtime implemented with notice, prompt, list, confirm, and completion overlay shells;
- Phase 2B modal interaction polish implemented with hover, pressed, focused/default, cancel, Enter/Escape/Tab keyboard routing, and compact dark control visuals;
- Phase 2C host-boundary cleanup implemented: SDL input translation now lives in `LunaHostSDL`, the demo consumes platform-neutral Luna input events, and UI colors are hex-configurable theme tokens instead of hardcoded demo colors;
- Phase 2D layout/resize/accessibility reflow implemented with `LunaLayout`, viewport-driven demo frames, modal reflow, and tests proving draw/hit-test/accessibility bounds stay synchronized after resize;
- Phase 2D.1 modal text/content reflow implemented so modal titles ellipsize, body text wraps/clips inside panel content bounds, and accessibility exposes full semantic text while using reflowed content regions;
- Phase 2D.2 universal bounded-text primitive implemented so semantic widgets, modal labels, prompt fields, status lines, and future controls use shared clip/ellipsize/wrap behavior while accessibility keeps full semantic labels;
- Phase 2D.3 responsive modal control layout implemented so modal buttons/choice rows use adaptive insets, sane preferred/minimum widths, full-width emergency-narrow single-button layout, and vertical stacking when multi-button rows cannot fit;
- Phase 2E visual style token lockdown implemented with product-neutral component theme tokens for editor, chrome, menus, panels, text fields, tabs, sidebar, status bar, diagnostics, and controls;
- product-neutral theme API cleanup completed so Moth-specific names are not part of Luna's reusable public API;
- demo-only Moth Obsidian theme added inside `LunaUITestApp`, proving applications can supply exact theme tokens without naming the product in the Luna library;
- renderer color contract fixed so logical RGBA hex colors flow through Luna's framebuffer and SDL presentation path without alpha/channel-order swaps;
- demo theme switching implemented through `1` = Luna demo blue, `2` = demo-only Moth Obsidian, and `3` = high-contrast proof theme, proving Luna widgets/modals draw from active theme variables;
- roadmap expanded to include resize/layout/accessibility reflow, visual token lockdown, product-neutral theme boundaries, renderer color correctness, text view phases, editor UI surfaces, chrome, and public API stabilization;
- HybX / Hybrid RobotiX credited as architectural influence.

The next implementation target is:

```text
Phase 3A — Static Accessible Text View
```

Phase 2E is complete. The next step is to build the first static, resize-safe, accessibility-aware Luna text-view primitive using the locked visual tokens and renderer color contract.

For a concise checkpoint, see [`docs/CURRENT_STATUS.md`](docs/CURRENT_STATUS.md).

---

## Phase Test Commands

Architecture tests:

```bash
swift build --target LunaArchitectureTests
swift test --filter LunaArchitectureTests
```

Phase 1 semantic widget tests:

```bash
swift build --target LunaUIPhase1Tests
swift test --filter LunaUIPhase1Tests
```

Phase 2 modal/overlay tests:

```bash
swift build --target LunaUIPhase2Tests
swift test --filter LunaUIPhase2Tests
swift test --filter LunaUIPhase2DTests
swift build --target LunaUIPhase2ETests
```

Full Linux check:

```bash
rm -rf .build
swift build
swift test --filter LunaUIPhase1Tests
swift test --filter LunaUIPhase2Tests
swift test --filter LunaUIPhase2DTests
swift test --filter LunaUIPhase2ETests
swift run LunaUITestApp
```

---

## Non-Goals

Luna UI does not aim to:

- replace SwiftUI for normal app development;
- become a universal Qt/GTK competitor;
- provide visual designers or drag-and-drop GUI builders;
- chase native platform look-and-feel conventions;
- optimize for rapid prototyping over correctness;
- hide rendering details behind opaque abstractions;
- become the Moth Text application itself.

Luna is intentionally narrow so it can be brutally good at editor-class custom UI.

---

## Why Swift

Swift is a deliberate choice. It provides strong typing, value semantics, predictable performance, memory safety, and direct access to native platform capabilities without committing the project to C++ complexity or Rust friction in UI-heavy code.

Swift the language is the tool.

SwiftUI the framework is the wrong abstraction for this project.

---

## What Luna Enables in Moth Text

Luna makes the following realistic:

- pixel-perfect cursor and selection rendering;
- consistent glyph shaping across platforms;
- explicit layout and paint pipelines;
- fast redraw and damage tracking for large files;
- Sublime-style theme compatibility;
- custom command palette, quick panel, completion popup, and status UI;
- accessible custom widgets and text views;
- clean separation between editor logic and UI infrastructure.

For Moth Text, Luna is the difference between fighting a framework and owning the editor.

---

## License

See [`LICENSE`](LICENSE).
