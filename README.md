# Luna UI

**Luna UI** is a from-scratch, cross-platform family of UI, rendering, text, document, and developer-tool libraries written in Swift. It is the foundational UI stack for **Moth Text**, a future Sublime-class text editor, while remaining reusable for unrelated desktop applications.

This repository is **not Moth Text**.

This repository is the shared Luna stack.

Luna owns reusable mechanisms: rendering, layout, text shaping, input routing, theming, widgets, accessibility semantics, commands, overlays, platform hosting, and optional document/editor-oriented components. Moth sits above Luna and owns editor meaning, workflow, compatibility, and product policy. Editor-adjacent functionality is welcome in Luna when it is optional, product-neutral, and usable by other applications.

---

## Current Roadmap Documents

The project direction is split into two roadmap documents:

- [`docs/LUNA_UI_ROADMAP.md`](docs/LUNA_UI_ROADMAP.md) — engine/runtime roadmap for Luna UI.
- [`docs/MOTH_TEXT_ROADMAP.md`](docs/MOTH_TEXT_ROADMAP.md) — editor-product roadmap for Moth Text.
- [`docs/LUNA_UI_DEMO_TEST_PROTOCOL.md`](docs/LUNA_UI_DEMO_TEST_PROTOCOL.md) — current LunaUITestApp manual regression protocol.
- [`docs/LUNA_LAYERED_ARCHITECTURE.md`](docs/LUNA_LAYERED_ARCHITECTURE.md) — governing boundary between Luna foundation, general UI, optional document/editor components, and Moth product policy.
- [`docs/PAIRED_ITERATION_PROTOCOL.md`](docs/PAIRED_ITERATION_PROTOCOL.md) — required Luna-first build, test, commit, and Moth submodule-consumption workflow.

The short version:

```text
Luna Foundation/General UI = reusable runtime, rendering, widgets, accessibility
Luna Document/Editor UI    = optional reusable document and developer-tool components
Moth Text                  = Sublime-class editor product and compatibility policy
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
  Source-editor behavior, production buffers, projects, settings, packages, Sublime compatibility.

Luna Document / Editor Components
  Optional reusable text surfaces, document workspaces, search UI, gutters, completion, diff/log tools.

Luna General UI
  Reusable widgets, layouts, overlays, menus, focus, commands, and accessibility.

Luna Foundation / Render / Text / Theme / Host
  Core identities, rendering, shaping, styling, and platform-specific host bridges.
```

Moth Text defines **what the editor means and how its product workflow behaves**.

Luna defines **the reusable mechanisms and optional component anatomy** used to draw, interact with, host, theme, and expose applications semantically.

This means Moth should not own renderer backends, SDL/AppKit/Metal imports, accessibility bridges, generic overlays, command-palette UI, completion-popup UI, menus, or the platform event loop. Luna may also ship optional reusable editor-adjacent components, but Moth retains production source-buffer behavior, multiple-cursor semantics, project/session policy, language services, and Sublime compatibility.

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

Run the Phase 5D real-file proof with a local UTF-8 text file:

```bash
swift run LunaUITestApp --open README.md
# also supported:
swift run LunaUITestApp README.md
LUNA_DEMO_OPEN_FILE=README.md swift run LunaUITestApp
```

Run the Phase 5D.1 checked-in public-domain demo corpus:

```bash
swift run LunaUITestApp --open-demo-corpus=largest
swift run LunaUITestApp --open-demo-corpus=frankenstein
swift run LunaUITestApp --open-demo-corpus=caesar
swift run LunaUITestApp --open-demo-corpus=all
./scripts/run-demo-corpus.sh --largest
```

Verify the corpus manifest:

```bash
./scripts/verify-public-domain-demo-files.py
```

Run the Phase 5D.2 new-file and untitled-buffer proof:

```bash
# Open an empty in-memory untitled buffer. Ctrl+N / File > New File does the same interactively.
swift run LunaUITestApp --new-untitled

# Create a new empty local file safely, without overwriting an existing file.
mkdir -p /tmp/luna-ui-new-file-proof
swift run LunaUITestApp --create /tmp/luna-ui-new-file-proof/new-note.txt

# Seed the scripted Save As dialog target, then choose File > Save As… in the app.
swift run LunaUITestApp --new-untitled --save-as /tmp/luna-ui-new-file-proof/untitled-saved-as.txt
```

Run the Phase 5D.3 native-dialog boundary proof:

```bash
# File > Open… uses a native desktop helper when available. For repeatable tests, script the dialog result:
swift run LunaUITestApp --dialog-open README.md

# Save on an untitled dirty document now asks for a Save As destination.
swift run LunaUITestApp --new-untitled --save-as /tmp/luna-ui-new-file-proof/native-save-as.txt

# Dirty close can be scripted for regression testing; interactive runs use the host dialog provider.
LUNA_DEMO_DIALOG_UNSAVED_DECISION=discard swift run LunaUITestApp --new-untitled
```

On Linux, the interactive demo looks for desktop dialog helpers (`zenity`, `yad`, then `kdialog`) and keeps CLI/scripted paths as the deterministic fallback. This is a host/app boundary, not a LunaUI widget dependency; LunaUI still owns only neutral document/workspace/dialog request seams.


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
- Phase 3A static accessible text view implemented with read-only document lines, gutter/text viewport layout, current-line paint geometry, visible line text ranges, hit testing, and accessibility text-run children;
- Phase 3B caret geometry and static selection implemented with stable text locations, caret rectangles, selection rectangles, text-coordinate hit testing, and accessibility caret/selection metadata;
- Phase 3C text-view scrolling and viewport metrics implemented with logical line scroll state, visible line ranges, content height, scrollbar placeholder geometry, scrolled hit testing, and accessibility visible text ranges;
- Phase 3D editable text-input foundation implemented with a small mutable document/state layer, committed text-input events, insertion/newline/backspace/delete, selection replacement, caret movement, and editable accessibility metadata;
- Phase 4A command palette / quick panel foundation implemented with generic Luna quick-panel items, deterministic filtering, query state, selected rows, keyboard navigation, Enter activation, Escape dismissal, pointer row activation, accessibility dialog/list nodes, and a demo command palette opened with Ctrl+P;
- Phase 4A.1 LunaUITestApp demo layout cleanup completed with a readable header, main editor area, side proof panel, bottom status bar, and constrained moving animation so debug/iteration info no longer stacks over the editor;
- Phase 4B generic find / replace panel foundation implemented with reusable find query/options/results, literal/regex scanning, whole-word/case toggles, replace-current/replace-all operations, text-view match highlights, keyboard/pointer interaction, theme-driven panel visuals, accessibility nodes, and a demo panel opened with Ctrl+F;
- Phase 4B.1 interactive text selection completion implemented with click-drag selection, Shift-click extension, Shift+Left/Right extension, plain-arrow selection collapse, selection replacement/delete behavior, and pointer modifier propagation through LunaInput;
- demo theme switching now routes through command palette/menu commands instead of bare number hotkeys, proving Luna widgets/modals/text surfaces draw from active theme variables while the editor can type numbers normally;
- Phase 4C product-neutral menu bar/dropdown foundation implemented with top menus, dropdown rows, disabled/checked states, shortcut display, first-pass submenus, pointer/keyboard interaction, theme-driven rendering, accessibility nodes, and demo command dispatch;
- Phase 4D product-neutral editor shell foundation implemented with reusable tab strip, sidebar tree/list, editor content frame, status-bar segments, pointer interaction, theme-driven geometry, visible demo labels, and accessibility nodes;
- Phase 4E product-neutral context menu foundation implemented with secondary-click floating menus, reused menu items/dropdown rows, editor/tab/sidebar/status context definitions, disabled/checked/separator/submenu states, pointer/keyboard routing, accessibility nodes, and demo command dispatch;
- Phase 4F product-neutral completion popup foundation implemented with caret/anchor positioning, app-supplied completion items, selected rows, detail text, keyboard/pointer activation, insertion/command payloads, theme-driven geometry, visible demo labels/details, and accessibility list/list-item nodes;
- Phase 5A real document / buffer integration implemented with product-neutral document descriptors, open buffer storage, active-document routing, per-document caret/selection/scroll preservation, dirty tracking from editable text revisions, shell-tab projection, and demo tabs/sidebar rows that switch the actual editor buffer;
- Phase 5B product-neutral command runtime implemented with command context, dynamic availability, key binding matching, surface projection, runtime handler execution against an app-owned host, and demo menu/palette/context/keyboard dispatch through one command path;
- Phase 5C file/project adapter boundary implemented with product-neutral file/project IDs, file descriptors, project tree snapshots, workspace state, sidebar projection helpers, open/save contracts, dirty-close policy, and an in-memory demo adapter proving file/project seams without real Moth policy;
- Phase 5C.1 frame pacing/invalidation runtime boundary implemented with host timing stats, frame requests, invalidation reasons, frame pacing helpers, SDL vsync/delay cleanup, and runtime diagnostics;
- Phase 5C.2 editor harness split and input coalescing implemented with default editor mode, optional proof-gallery mode, host pointer-motion coalescing, state-change pointer invalidation, quiet command logging by default, and input/event diagnostics;
- Phase 5C.2.1 targeted tab/document close routing implemented with context-carried target document IDs, tab-close command routing through dirty-close policy, context-menu command attributes, active/workspace/shell state synchronization after close, and regression coverage for command-context targeting;
- Phase 5C.2.2 MPL-2.0 license migration completed with the repository license text updated, source/test/shim files carrying SPDX headers, and documentation aligned around the new license;
- Phase 5D real file I/O proof implemented with an app-owned local-file adapter in `LunaUITestApp`, `--open` launch paths, real UTF-8 file loading, local save/save-all through `LunaDocumentSaveResult`, and file errors surfaced as demo status instead of LunaUI policy;
- Phase 5D.1 public-domain demo corpus integrated under `Examples/PublicDomainDemoFiles`, with manifest verification, helper launch scripts, and `--open-demo-corpus` options for repeatable real-file demos;
- Phase 5D.2 new-file lifecycle proof implemented with Ctrl+N/File > New File untitled buffers, `--new-untitled`, safe `--create` empty local-file launch support, demo Save As routing, no-overwrite defaults, and untitled/file-backed state transitions kept outside LunaUI filesystem policy;
- Phase 5D.3 host dialog boundary implemented with neutral LunaHostCore dialog service request/result types, scripted test doubles, interactive Open… / Save As… / dirty-close routing in `LunaUITestApp`, Linux/macOS desktop-helper bridges, and a deliberate seam for future Luna-rendered file-management widgets without making LunaUI own OS dialog policy;
- Phase 5D.3.1 proof-gallery animation pacing implemented with a LunaHostCore animation clock, clamped logical animation deltas, animation invalidation diagnostics, and cleanup of duplicate demo chrome drawing while keeping the default editor harness event-driven;
- Phase 5D.3.2 proof-gallery frame-cache optimization implemented with animation-only static-frame reuse, explicit framebuffer copy support, and removal of reflection from the presenter pixel-upload path so the legacy moving-square stress proof stays smooth without changing editor-mode invalidation policy;
- Phase 5E.1 reusable SDL application lifecycle implemented with a public downstream scene contract, normalized host events, invalidation-driven presentation, and an application-owned termination veto seam for unsaved-document policy;
- Phase 5E.2 document/view adapter seams implemented with immutable UTF-8 snapshots, stable revisions, independent presentation state, injected find sessions, and public diagnostic bitmap text rendering;
- Phase 5F.1 workspace mechanics implemented with recursive product-neutral pane trees, split geometry, active-pane routing, directional and wrapping focus traversal, divider resizing, pane command context, pinned-tab layout, deterministic tab overflow, and overflow presentation state;
- Phase 5F.2A pane-bound editor surfaces implemented with product-neutral content frames, independent clipped bounds, width-correct soft wrapping, visual-row scrolling, and per-pane reflow;
- Convergence C1A native cursor intent, SDL cursor mapping, drag-time pointer capture, forgiving semantic divider controls, and shared pane hover/drag state implemented;
- Convergence C1B reusable text-selection gesture interpretation implemented with click, Shift-click, captured drag, Unicode word/logical-line units, wrapped-row tracking, and edge autoscroll;
- Convergence C2 completed as a deliberate Luna source freeze: Moth now owns document history, inverse edits, grouping, view restoration, and saved-checkpoint semantics without requiring a new Luna production API;
- roadmap expanded to include resize/layout/accessibility reflow, visual token lockdown, product-neutral theme boundaries, renderer color correctness, text view phases, editor UI surfaces, chrome, and public API stabilization;
- HybX / Hybrid RobotiX credited as architectural influence.

The current implementation checkpoint is:

```text
Convergence C2 — Moth document-owned undo/redo, Luna source-frozen
```

Luna's C1B public surface proved sufficient for C2. Moth now owns monotonic-revision-safe Undo/Redo, deterministic transaction grouping, multi-view restoration, redo branching, and saved-history checkpoint semantics. No Luna production source was changed for C2. The next paired slice is Moth M2.2B command and visible-find convergence; Luna changes only for a genuinely reusable presentation or command seam.

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

Phase 3 text-view tests:

```bash
swift build --target LunaUIPhase3ATests
swift test --filter LunaUIPhase3ATests
swift build --target LunaUIPhase3BTests
swift test --filter LunaUIPhase3BTests
swift build --target LunaUIPhase3CTests
swift test --filter LunaUIPhase3CTests
swift build --target LunaUIPhase3DTests
swift test --filter LunaUIPhase3DTests
```

Phase 4 surface tests:

```bash
swift build --target LunaUIPhase4ATests
swift test --filter LunaUIPhase4ATests
swift build --target LunaUIPhase4BTests
swift test --filter LunaUIPhase4BTests
swift build --target LunaUIPhase4CTests
swift test --filter LunaUIPhase4CTests
swift build --target LunaUIPhase4DTests
swift test --filter LunaUIPhase4DTests
swift build --target LunaUIPhase4ETests
swift test --filter LunaUIPhase4ETests
swift build --target LunaUIPhase4FTests
swift test --filter LunaUIPhase4FTests
```

Phase 5 editor-surface deepening tests:

```bash
swift build --target LunaUIPhase5ATests
swift test --filter LunaUIPhase5ATests
swift build --target LunaUIPhase5BTests
swift test --filter LunaUIPhase5BTests
swift build --target LunaUIPhase5CTests
swift test --filter LunaUIPhase5CTests
swift build --target LunaHostPhase5C1Tests
swift test --filter LunaHostPhase5C1Tests
swift build --target LunaUIPhase5F1Tests
swift test --filter LunaUIPhase5F1Tests
swift build --target LunaUIPhase5F2ATests
swift test --filter LunaUIPhase5F2ATests
swift build --target LunaUIConvergenceC1ATests
swift test --filter LunaUIConvergenceC1ATests
swift build --target LunaUIConvergenceC1BTests
swift test --filter LunaUIConvergenceC1BTests
```

Full Linux check:

```bash
rm -rf .build
swift build
swift test --filter LunaUIPhase1Tests
swift test --filter LunaUIPhase2Tests
swift test --filter LunaUIPhase2DTests
swift test --filter LunaUIPhase2ETests
swift test --filter LunaUIPhase3ATests
swift test --filter LunaUIPhase3BTests
swift test --filter LunaUIPhase3CTests
swift test --filter LunaUIPhase3DTests
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

Luna-UI is licensed under the Mozilla Public License 2.0 (`MPL-2.0`). See [`LICENSE`](LICENSE) for the full license text.

Source, test, package-manifest, system-shim, and module-map files carry concise SPDX headers:

```text
SPDX-License-Identifier: MPL-2.0
```

The project intentionally uses SPDX headers instead of pasting the full license block into every source file. The full terms live in `LICENSE`.


### Demo modes

Default run uses the editor harness, which is the Moth-like performance baseline:

```bash
swift run LunaUITestApp
```

Proof-gallery mode keeps old phase visual/stress surfaces available without putting them on the default hot path:

```bash
swift run LunaUITestApp --proof-gallery
# or
LUNA_DEMO_MODE=proof swift run LunaUITestApp
```

Command-request stdout logging is disabled by default. Enable it only when debugging command routing:

```bash
LUNA_DEMO_DEBUG_COMMANDS=1 swift run LunaUITestApp
```

### Reusable Linux Application Host

`LunaHostSDL` now exposes the same invalidation-driven Linux window lifecycle
used by `LunaUITestApp`. Downstream applications provide a platform-neutral
`LunaSDLApplicationScene`; Luna owns SDL initialization, input normalization,
framebuffer presentation, resizing, pacing, and shutdown.
