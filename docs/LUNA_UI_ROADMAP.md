# Luna UI Roadmap

Luna UI is the Swift-native application engine underneath Moth Text. It is not a wrapper around SwiftUI, AppKit widgets, GTK, Qt, Electron, or a web stack. Luna owns the editor-facing UI stack: input, layout, paint, rendering, accessibility semantics, commands, themes, overlays, widgets, and platform hosting.

This roadmap merges the original Luna UI goals with the HybX / Hybrid RobotiX architecture pass and the Sublime Text visual references collected for Moth Text. The original Luna goals remain intact: custom rendering, text shaping, GPU rendering with CPU fallback, cross-platform parity, Sublime-style theme compatibility, and a public reusable API. The HybX influence adds the semantic runtime spine: accessibility from day one, typed commands, widget identity, modal overlays, live announcements, and a hard boundary between app policy and platform glue.

Hybrid RobotiX / HybX is credited as an architectural influence. Luna does not vendor or port HybX Rust code. See: <https://codeberg.org/hybridrobotix>

---

## Product Definition

Luna UI is:

- a from-scratch UI and rendering engine written in Swift;
- a reusable engine, not the Moth Text application itself;
- cross-platform by design, with macOS and Linux as first-class targets;
- custom-drawn and editor-first;
- accessibility-first, command-driven, and semantically structured;
- renderer-backend independent, with CPU as correctness reference and GPU as production direction;
- visually shaped by the goal of building a Sublime-class editor.

Luna UI is not:

- a SwiftUI app;
- an AppKit clone;
- a GTK/Qt/Electron wrapper;
- a general-purpose consumer UI toolkit;
- a place for Moth-specific editor policy;
- a place for platform C APIs to leak upward into app/editor code.

---

## Architectural Doctrine

The most important rule:

> If Luna can draw a widget, Luna must also be able to describe it semantically.

Every real widget must eventually participate in these systems:

- stable identity;
- explicit bounds;
- layout and resize behavior;
- display list generation;
- hit testing;
- focus behavior;
- command/action behavior where appropriate;
- accessibility node generation;
- accessibility children;
- live announcement behavior where appropriate;
- theme/style resolution.

This prevents the classic custom-UI failure where the visible UI, clickable UI, and screen-reader UI become three different realities.

Critical geometry law:

```text
draw bounds = hit-test bounds = accessibility bounds
```

Critical boundary law:

```text
Only host targets translate platform input.
Only renderer targets own renderer backend details.
Only theme/style code decides colors.
App/demo/editor code talks to Luna through typed Swift APIs.
```

---

## Visual Direction

Luna is reusable, but its default editor-facing visual language is shaped by Moth Text and Sublime Text references.

Default Moth/Sublime-like direction:

- dark editor-first interface;
- blue-gray editor/content area;
- charcoal chrome, overlays, menus, and panels;
- compact tabs, menus, rows, and controls;
- thin borders and restrained contrast;
- subtle cyan/teal hover and selection accents;
- rectangular controls with low radius;
- no bubbly mobile-style controls;
- no Electron/VS Code/JetBrains visual language by default;
- keyboard-first overlays and menus.

Menu dropdowns may innovate, but the baseline behavior should remain Sublime-compatible where applicable. The menu system should preserve expected Sublime command coverage while allowing better search, descriptions, discoverability, and accessibility.

Color customization is mandatory. Moth Text must be able to supply exact hex-driven theme values for every major UI role, including editor, gutter, selection, caret, menu rows, tabs, sidebar, status bar, overlays, buttons, scrollbars, minimap, warnings, and accents.

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

LunaInput
  Platform-neutral pointer, keyboard, window, and host events.

LunaTextCore
  Pure text/glyph data structures that do not require HarfBuzz/FreeType.

LunaText
  Font lookup, shaping, ligatures, bidi, combining marks, glyph runs, metrics.

LunaRender
  Backend-independent display lists, CPU renderer, framebuffer contract, GPU path.

LunaTheme
  Color primitives, hex parsing, theme tokens, control styles, contrast-aware palettes, Sublime color scheme import later.

LunaHostCore
  Platform-neutral window/input/timing/clipboard/accessibility host contracts.

LunaHostSDL
  SDL-backed Linux/macOS host boundary. SDL imports and SDL event normalization stay here.

LunaHostMetal
  macOS Metal renderer/host path. Metal/AppKit imports stay here.

LunaUI
  Widgets, layout, focus, overlays, menus, prompts, status bars, UI context.

LunaUITestApp
  Proof application only. It exercises Luna the way Moth will use Luna, but it does not become the engine.
```

---

# Implementation Phases

## Phase 0 — Architecture Baseline

**Status:** complete/current foundation.

Purpose: establish Luna as a Swift-native, custom-drawn, accessibility-first UI engine while preserving the original renderer/text/theme/platform goals.

Deliverables:

- architecture spine added;
- Linux SwiftPM/SDL2 build fixed;
- Swift 6.2 SDL enum/stderr issues fixed;
- framebuffer/text coordinate mirroring bug fixed;
- README credit for HybX / Hybrid RobotiX;
- roadmap documents added.

Definition of done:

- `swift build` passes on Linux;
- architecture tests pass;
- demo runs;
- Luna states that accessibility, commands, theming, host boundaries, and semantic widgets are core infrastructure.

---

## Phase 1 — Semantic Widget Contract

### Phase 1A — Semantic Widget Proof

**Status:** complete.

Goal: prove one widget can exist as a real semantic Luna object.

Scope:

- stable `LunaNodeID`;
- explicit bounds;
- display-list output;
- hit testing;
- accessibility node generation;
- accessibility children;
- command request;
- `LunaUIContext` announcement;
- theme-derived colors.

Demo requirement:

- demo renders a real semantic widget rather than hand-drawn fake UI.

Tests required:

- display list generation;
- hit testing;
- accessibility node generation;
- activation queues command;
- disabled state blocks activation.

Definition of done:

- the same widget state drives rendering, interaction, and accessibility.

### Phase 1B — Pointer Routing

**Status:** complete.

Goal: prove pointer input reaches semantic widgets.

Scope:

- `LunaPointerEvent`;
- primary-click handling;
- hit/miss behavior;
- widget activation;
- command request path;
- visible status update;
- terminal command log.

Demo requirement:

- click inside widget activates it;
- click outside reports miss.

Tests required:

- inside click activates;
- outside click misses;
- non-primary buttons do not activate.

Definition of done:

```text
draw -> hit test -> activate -> command -> status update
```

---

## Phase 2 — Modal / Overlay / Interaction / Host Cleanup

Phase 2 is intentionally split into implementation gates. It is the bridge between “one widget works” and “Luna can support Sublime/Moth-style UI surfaces.”

### Phase 2A — Modal Overlay Runtime

**Status:** complete.

Goal: create reusable overlay infrastructure.

Scope:

- `LunaModalOverlay`;
- `LunaModalOverlayManager`;
- prompt shell;
- list / quick-panel shell;
- confirm shell;
- notice shell;
- completion shell;
- modal accessibility tree;
- modal-first pointer routing.

Demo requirement:

- click semantic widget opens modal overlay;
- modal draws above background;
- modal consumes clicks before background widgets;
- OK dismisses modal.

Tests required:

- modal opens;
- modal dismisses;
- background clicks are consumed;
- overlay accessibility nodes exist;
- modal choices can queue commands.

### Phase 2B — Modal Interaction Polish

**Status:** complete.

Goal: make controls behave like real UI controls, not static rectangles.

Scope:

- hover state;
- pressed state;
- focused/default state;
- disabled state;
- cancel/default choice metadata;
- Enter / Space activation;
- Escape cancel;
- Tab focus cycling;
- compact Sublime/Moth dark visuals.

Visual reference target:

```text
Sublime-style restrained interaction:
  subtle hover fill
  darker pressed state
  compact rectangular controls
  low-radius corners
  no bubbly modern buttons
  no giant web-app padding
```

Demo requirement:

- OK button visibly changes on hover and press;
- Enter activates;
- Escape dismisses.

Tests required:

- hover changes state;
- press changes state;
- mouse-up inside activates;
- mouse-up outside cancels press;
- Tab moves focus;
- Enter activates focused/default choice;
- Escape activates cancel choice.

### Phase 2C — Host Boundary and Theme Customization Cleanup

**Status:** complete/current checkpoint.

Goal: correct architectural debt where the demo was manually interpreting SDL, and make visual styling app/theme-driven rather than hardcoded.

Scope:

- `LunaInput`;
- `LunaHostInputEvent`;
- `LunaSDLInputTranslator`;
- SDL mouse/key/window normalization in `LunaHostSDL`;
- demo consumes Luna events instead of SDL keycodes;
- `LunaColor`;
- hex parsing for `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`;
- `LunaControlColorSet`;
- `LunaUIThemeColors`;
- `LunaTheme.mothDefaultDark`;
- theme-driven widget/control colors.

Architecture rule:

```text
SDL stays below LunaHostSDL.
Demo and Moth consume Luna events, not SDL keycodes.
```

Color rule:

```text
Widgets do not own hardcoded colors.
Themes/styles own colors.
Moth can supply exact custom hex colors.
```

Demo requirement:

- demo behaves the same but routes through LunaInput/LunaHostSDL and theme tokens.

Tests required:

- hex parsing works;
- theme colors flow into controls;
- custom theme affects widget rendering;
- SDL translator maps known keys/buttons/window events into Luna events.

### Phase 2D — Layout, Resize, and Accessibility Reflow

**Status:** complete.

Goal: make resize/layout/accessibility correctness real before building the text view.

Scope:

- `LunaViewport`;
- `LunaLayoutContext`;
- `LunaLayoutResult`;
- root scene layout in the demo;
- anchored layout primitives;
- modal recentering/reflow;
- widget reflow on resize;
- hit-test bounds update after resize;
- accessibility bounds update after resize.

Critical law:

```text
draw bounds = hit-test bounds = accessibility bounds
```

Demo requirement:

- resize the window;
- semantic widget repositions/reflows correctly;
- modal stays centered or clamps into visible area;
- OK button remains clickable after resize;
- accessibility node bounds regenerate from new layout;
- demo intentionally flexes the resize path rather than relying on fixed coordinates.

Tests required:

- layout changes with viewport;
- hit testing uses new bounds;
- modal button bounds update after viewport resize;
- accessibility node bounds match post-layout bounds.

Definition of done:

- the demo becomes a resize/reflow testbed, not fixed-position proof art.

### Phase 2D.1 — Modal Text Reflow and Clipping

**Status:** complete.

Goal: correct the first content-level resize bug found after Phase 2D: the modal panel reflowed, but title/body text still behaved like it had infinite width.

Scope:

- modal title text bounds derive from reflowed panel bounds;
- long modal titles ellipsize instead of spilling outside the dialog;
- modal body text wraps to the current content width;
- body text clips to the available message region instead of covering buttons;
- prompt/choice labels ellipsize inside their assigned control bounds;
- accessibility nodes continue exposing the full semantic title/body even when the visual debug font ellipsizes or clips;
- content-aware modal height can grow when narrow wrapping needs extra vertical room and the viewport allows it.

Critical law:

```text
panel reflow is not enough;
content must respect the reflowed panel regions too
```

Demo requirement:

- resize the modal narrow;
- title does not spill outside the panel;
- body wraps into multiple lines;
- body does not overlap the OK/choice row;
- OK remains clickable after resize.

Tests required:

- narrow modal title ellipsizes within title bounds;
- body text wraps within panel content width;
- body text does not overlap choice bounds;
- accessibility message bounds follow the reflowed message region;
- content-aware modal layout grows taller when wrapping requires extra lines and viewport space exists.

Definition of done:

- modal box geometry, hit testing, accessibility bounds, and visible text content all respond correctly to resize.


### Phase 2D.2 — Universal Bounded Text and Control Reflow

**Status:** complete.

Goal: promote the modal-only text reflow fix into a shared Luna primitive so every text-bearing control respects assigned bounds.

Scope:

- `LunaBoundedTextLayout`;
- `LunaBoundedTextLine`;
- `LunaTextOverflowMode`;
- `LunaTextHorizontalAlignment`;
- `LunaDebugTextMetrics`;
- shared clip, tail-ellipsis, and word-wrap behavior;
- semantic widget title/subtitle layout through bounded text;
- modal choice/button labels through bounded text;
- prompt/status/control labels prepared for the same primitive;
- full semantic text preserved for accessibility even when visual text is clipped or ellipsized.

Critical law:

```text
text-bearing widgets never draw as if they have infinite width
```

Demo requirement:

- semantic widget title/subtitle text stays inside its panel while resizing;
- modal title/body/choice labels stay inside their visual regions;
- status text ellipsizes inside the status region;
- accessibility labels keep the full underlying strings.

Tests required:

- bounded text ellipsizes single-line labels;
- bounded text wraps and clips multi-line body content;
- semantic widget title/subtitle use bounded text;
- modal choice labels use bounded text;
- accessibility exposes full semantic labels while visual text is constrained.

### Phase 2E — Visual Style Token Lockdown

**Status:** planned; can be implemented with or immediately after 2D.

Goal: formalize the Sublime/Moth visual language from the screenshot references.

Scope:

- `MothDefaultDarkTheme` tokens;
- menu colors;
- overlay colors;
- button colors;
- quick-panel row colors;
- status bar colors;
- tab colors;
- sidebar colors;
- editor/gutter/minimap colors;
- focus/accent colors;
- disabled colors;
- selection colors;
- missing-token/debug fallback policy.

Visual reference:

```text
dark charcoal chrome
blue-gray editor area
compact menu rows
cyan/teal hover/selection accent
subtle active top-menu underline
compact tab strip
thin status bar
low-noise panels
rectangular controls
right-aligned shortcuts
minimal submenu arrows
```

Demo requirement:

- demo can switch between at least two themes:
  - Luna demo theme;
  - Moth default dark theme;
- custom test theme visibly overrides important colors.

Tests required:

- theme tokens resolve;
- control state colors resolve;
- custom theme overrides defaults;
- no core widget requires hardcoded colors except explicit debug/missing-token fallback.

---

## Phase 3 — Accessible Text View

Phase 3 should not begin until Phase 2D/2D.1/2D.2 are complete. Phase 2D, 2D.1, and 2D.2 are complete; Phase 2E may still refine the visual tokens before Phase 3A begins.

### Phase 3A — Static Accessible Text View

Goal: draw and expose text semantically.

Scope:

- `LunaTextView`;
- text content;
- bounds/layout;
- visible lines;
- caret drawing;
- current line highlight;
- selection rendering placeholder;
- accessibility text node;
- accessibility text ranges;
- theme-driven text/background/caret/selection colors.

Demo requirement:

- demo shows a Sublime-like editor panel with text, gutter-like spacing, caret, and theme colors;
- resize updates text view bounds;
- accessibility bounds match visual bounds.

Tests required:

- text view builds display list;
- caret rect is correct;
- accessibility node exposes text role/value;
- theme colors flow into text view;
- resize updates text view layout.

### Phase 3B — Editable Text Input

Goal: make the text view interactive.

Scope:

- keyboard focus;
- typing;
- backspace/delete;
- enter;
- arrow keys;
- click to move caret;
- basic selection;
- copy/paste path prepared;
- text changed event/command;
- accessibility update after edit.

Demo requirement:

- click text view, type text, move caret, delete text.

Tests required:

- typing mutates text;
- caret moves;
- backspace/delete work;
- click positions caret;
- accessibility text updates after mutation.

### Phase 3C — Text View Scroll and Viewport

Goal: prepare for real editor usage.

Scope:

- scroll offset;
- visible line range;
- line height;
- content height;
- scrollbar/minimap lane placeholder;
- hit testing with scroll offset;
- accessibility visible text range.

Demo requirement:

- long text scrolls;
- caret and hit testing respect scroll position.

---

## Phase 4 — Sublime/Moth UI Surfaces

### Phase 4A — Command Palette / Quick Panel

Scope:

- quick panel overlay;
- filter input;
- selected row;
- keyboard navigation;
- Enter activation;
- Escape close;
- accessibility list roles.

Visual target: Sublime command palette and Goto Anything references.

### Phase 4B — Find / Replace Panel

Scope:

- bottom panel layout;
- find input;
- replace input;
- compact buttons;
- toggle icons/placeholders;
- keyboard handling;
- theme tokens.

Visual target: Sublime find and find/replace references.

### Phase 4C — Menu Bar and Dropdown Menus

Scope:

- top menu bar;
- dropdown rows;
- submenus;
- disabled items;
- checkbox items;
- shortcut alignment;
- hover/pressed/focused states;
- keyboard navigation;
- accessibility roles.

Visual target: Sublime menu screenshots.

Innovation allowed here:

- preserve 1:1 Sublime functionality where applicable;
- add better search/discovery/command descriptions/accessibility where useful.

### Phase 4D — Context Menu

Scope:

- right-click menu;
- compact rows;
- separators;
- disabled states;
- submenus;
- shortcut display.

### Phase 4E — Completion Popup

Scope:

- anchored popup;
- selected row;
- completion detail;
- keyboard navigation;
- mouse activation;
- accessibility list/item roles.

---

## Phase 5 — Editor Chrome Layout

### Phase 5A — Window Chrome Layout

Scope:

- menu bar;
- tab bar;
- main editor region;
- panel region;
- status bar.

### Phase 5B — Tabs

Scope:

- active tab;
- inactive tab;
- dirty tab state;
- close button area;
- tab overflow later.

Visual target: Sublime dirty tab and active/inactive tab references.

### Phase 5C — Sidebar

Scope:

- open files section;
- folders section;
- tree rows;
- hover/selection;
- disclosure arrows.

### Phase 5D — Status Bar

Scope:

- line/column;
- syntax mode;
- encoding;
- indentation;
- Git/status slots later.

### Phase 5E — Minimap / Scrollbar Lane

Scope:

- minimap placeholder;
- scrollbar lane;
- viewport indicator;
- theme tokens.

---

## Phase 6 — Renderer and Snapshot Correctness

This phase can happen partly in parallel, but it needs its own gates.

Scope:

- framebuffer coordinate contract;
- CPU renderer as reference;
- text orientation snapshot tests;
- display-list snapshot tests;
- dirty rect diagnostics;
- glyph bounds diagnostics;
- future GPU/Metal parity tests.

Important bugs to guard against:

- mirrored text;
- wrong origin;
- stale hit boxes;
- stale accessibility bounds;
- selection/caret mismatch.

---

## Phase 7 — Public API Stabilization

Scope:

- stable module boundaries;
- public exports;
- doc comments;
- theme API;
- widget API;
- layout API;
- input API;
- command API;
- accessibility API;
- host API.

Goal:

- Moth can depend on Luna cleanly;
- other apps could use Luna too.

---

## Immediate Next Implementation Target

The next implementation target is:

```text
Phase 2E — Visual Style Token Lockdown
```

Phase 2D, 2D.1, and 2D.2 are complete. Phase 2E should lock the reusable Sublime/Moth visual token set before text view/editor chrome work starts depending on those tokens.
