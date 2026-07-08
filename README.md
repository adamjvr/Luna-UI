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
Luna UI  = reusable Swift UI/runtime/rendering/accessibility engine
Moth Text = Sublime-class editor product built on Luna UI
```

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

### Command-Driven UI

Commands are shared infrastructure. Menus, shortcuts, command palettes, accessibility actions, tests, and eventually plugins should be able to call the same typed command IDs.

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

LunaText
  Font lookup, shaping, ligatures, bidi, combining marks, glyph runs, metrics.

LunaRender
  Display lists, CPU renderer, framebuffer contract, future GPU backends.

LunaTheme
  Theme tokens, color roles, style system, Sublime color scheme import later.

LunaHostCore
  Platform-neutral host contracts.

LunaHostSDL
  SDL-backed host boundary for Linux/macOS bring-up. SDL imports stay here.

LunaHostMetal
  macOS Metal path. Metal/AppKit details stay here.

LunaUI
  Widgets, layout, focus, overlays, menus, prompts, status bars, UI context.

LunaUITestApp
  Proof app only. It exercises Luna but should not become the engine.
```

Boundary rule:

> Platform code never leaks upward, renderer backend details never leak sideways, and Moth Text does not import platform UI APIs to draw normal editor UI.

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
- Phase 1 semantic widget proof implemented;
- Phase 1B live SDL mouse-click routing into the semantic widget implemented;
- Phase 2 modal/overlay runtime implemented with notice, prompt, list, confirm, and completion overlay shells;
- Phase 2B modal interaction polish implemented with hover, pressed, focused/default, cancel, Enter/Escape/Tab keyboard routing, and Sublime/Moth-style default control visuals;
- Phase 2C host-boundary cleanup started: SDL input translation now lives in `LunaHostSDL`, the demo consumes platform-neutral Luna input events, and UI colors are hex-configurable theme tokens instead of hardcoded demo colors;
- HybX / Hybrid RobotiX credited as architectural influence.

Expect refactors. The architecture is being made stricter on purpose so Moth Text does not become a tangled ball of editor, renderer, platform, accessibility, and file-system code.

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

## Phase 1 Semantic Widget Proof

```bash
swift build --target LunaUIPhase1Tests
swift test --filter LunaUIPhase1Tests
```

`LunaSemanticActionWidget` is the first real widget wired through the complete Luna contract.


## Phase 2 / 2B Modal and Overlay Runtime

```bash
swift build --target LunaUIPhase2Tests
swift test --filter LunaUIPhase2Tests
```

Phase 2 adds the first reusable Luna overlay runtime primitives:

- `LunaModalOverlay`;
- `LunaModalOverlayManager`;
- `LunaModalChoice`;
- `LunaModalInteractionResult`;
- concrete prompt, list, confirm, notice, and completion overlay construction from `LunaModalRequest`;
- modal-first pointer routing so overlays block background widgets;
- accessibility nodes for modal panels, static text, prompt fields, buttons, and list/completion choices.

Phase 2B polishes those shell controls into a real interaction model shaped by Sublime Text / Moth Text visuals:

- `LunaControlInteractionState`;
- `LunaMothDefaultDarkControlStyle`;
- hovered modal choice state;
- pressed modal choice state;
- focused/default choice state;
- cancel/default choice metadata;
- Enter/Space activation;
- Escape dismissal/cancel;
- Tab focus cycling;
- compact dark rectangular control colors with cyan/teal hover and focus accents.

The Linux demo now proves the path live: click the Phase 1B semantic panel to open a Phase 2B notice overlay. Hover over **OK**, hold the mouse down to see the pressed state, release to dismiss, or use Enter/Escape from the keyboard.


## Phase 2C Host Boundary and Theme Customization

Phase 2C corrects architectural debt exposed by the Phase 2B Linux demo work.
The demo is not allowed to become a side-channel around Luna. It must exercise
Luna the same way Moth Text eventually will.

Phase 2C adds:

- `LunaInput` platform-neutral pointer, keyboard, and host input events;
- `LunaSDLInputTranslator` inside `LunaHostSDL` for SDL-to-Luna event translation;
- SDL keycode/mouse/window-event normalization below the host boundary;
- a Linux demo loop that consumes `LunaHostInputEvent` instead of manually decoding SDL keycodes;
- `LunaColor` with hex parsing for `#RGB`, `#RGBA`, `#RRGGBB`, and `#RRGGBBAA`;
- `LunaControlColorSet` and `LunaUIThemeColors` for app-supplied UI/control colors;
- `LunaTheme.mothDefaultDark` as a default Sublime/Moth-shaped dark theme;
- theme-driven semantic widget and modal control colors.

The rule going forward:

```text
Rendering code draws pixels.
Widgets describe semantic intent and interaction state.
Themes decide colors.
Host targets translate platform input.
Apps decide which theme is active.
```

Moth Text will not be forced to inherit the current demo colors. It will supply
its own `LunaTheme`/`LunaUIThemeColors` values, with exact hex colors, for editor
backgrounds, chrome, tabs, sidebars, overlays, menus, buttons, selections,
scrollbars, minimap colors, and other UI elements.
