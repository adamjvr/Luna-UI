# Luna UI Roadmap

Luna is the Swift-native custom application stack underneath Moth Text and a reusable family of libraries for other desktop applications. It is not a wrapper around SwiftUI, AppKit widgets, GTK, Qt, Electron, or a web stack. Luna owns reusable mechanisms: input, layout, paint, rendering, accessibility semantics, commands, themes, overlays, widgets, platform hosting, and optional document/editor-oriented components. Moth owns source-editor meaning, workflow, compatibility, and product policy.

This roadmap merges the original Luna UI goals with the HybX / Hybrid RobotiX architecture pass and the Sublime Text visual references collected for Moth Text. The original Luna goals remain intact: custom rendering, text shaping, GPU rendering with CPU fallback, cross-platform parity, Sublime-style theme compatibility, and a public reusable API. The HybX influence adds the semantic runtime spine: accessibility from day one, typed commands, widget identity, modal overlays, live announcements, and a hard boundary between app policy and platform glue.

Hybrid RobotiX / HybX is credited as an architectural influence. Luna does not vendor or port HybX Rust code. See: <https://codeberg.org/hybridrobotix>

---

## Product Definition

Luna UI is:

- a from-scratch UI and rendering engine written in Swift;
- a reusable engine, not the Moth Text application itself;
- cross-platform by design, with macOS and Linux as first-class targets;
- custom-drawn and application-general, with unusually strong document/editor capabilities;
- accessibility-first, command-driven, and semantically structured;
- renderer-backend independent, with CPU as correctness reference and GPU as production direction;
- visually shaped by the goal of building a Sublime-class editor.

Luna UI is not:

- a SwiftUI app;
- an AppKit clone;
- a GTK/Qt/Electron wrapper;
- a native-control wrapper or lowest-common-denominator consumer toolkit;
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

Luna is reusable. Its built-in editor-facing defaults are shaped by Sublime-class editor requirements, but the reusable library must not expose product-specific names or palettes.

Default editor/Sublime-like direction:

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

Color customization is mandatory. Applications must be able to supply exact hex-driven theme values for every major UI role, including editor, gutter, selection, caret, menu rows, tabs, sidebar, status bar, overlays, buttons, scrollbars, minimap, warnings, and accents.

Product-specific color schemes belong in applications or demo fixtures. For example, LunaUITestApp may include a demo-only Moth palette, but LunaTheme/LunaUI public API names stay product-neutral.

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

LunaUI / future LunaWidgets
  General widgets, layout, focus, overlays, menus, prompts, status bars, UI context.

Optional Luna document/developer component targets
  Reusable editable text, document workspaces, gutters, search panels, completion,
  diff/log/console and other editor-adjacent components. These may begin inside
  LunaUI but must remain logically separable and optional.

Moth targets (separate product repository/targets)
  Production source buffers, editor transactions, multi-cursor behavior, projects,
  sessions, syntax, packages, language services, and Sublime compatibility.

LunaUITestApp
  Proof application only. It exercises Luna the way Moth and other apps will use
  Luna, but it does not become the engine or own public product policy.
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

**Status:** complete.

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
- product-neutral built-in defaults such as `LunaTheme.lunaDefaultDark`;
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
Applications can supply exact custom hex colors.
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

### Phase 2D.3 — Responsive Modal Control Layout

**Status:** complete.

Goal: correct the second content-level resize bug found after Phase 2D.2: text respected its bounds, but modal buttons/choice rows could still be assigned bad fixed-width/right-anchored bounds in very narrow viewports.

Scope:

- adaptive modal content insets;
- shared modal content bounds for title, body, fields, and controls;
- responsive horizontal choice/button layout;
- single-button rows become full-width inside the content column when the panel is too narrow for the preferred button width;
- multi-button rows shrink to a usable minimum, then stack vertically when they cannot fit horizontally;
- prompt field bounds follow the same adaptive content column;
- emergency-narrow message text ellipsizes instead of wrapping into one-character columns;
- choice/button labels remain bounded inside their responsive button frames;
- accessibility bounds continue to follow the actual reflowed control bounds.

Critical law:

```text
controls must choose sane bounds for the available viewport before text is laid out
```

Demo requirement:

- resize a notice modal extremely narrow;
- OK remains inside the modal panel;
- OK remains clickable;
- OK label remains inside the button;
- body text does not become a useless single-character column;
- multi-button confirm overlays stack rather than spilling outside the panel.

Tests required:

- notice OK button remains inside the panel in emergency-narrow viewports;
- single-button rows use full available content width when preferred width cannot fit;
- multi-button confirm rows stack vertically when too narrow for horizontal minimums;
- emergency-narrow message text ellipsizes instead of wrapping into one-character columns;
- button hit-test and accessibility bounds match the responsive button frame.

Definition of done:

- modal controls have responsive bounds, not merely bounded text inside broken bounds.

### Phase 2E — Visual Style Token Lockdown

**Status:** complete.

Goal: formalize Luna's product-neutral visual token surface before building the text view, menus, quick panels, tabs, sidebar, status bar, and editor chrome.

Scope:

- product-neutral built-in defaults such as `LunaTheme.lunaDefaultDark` and `LunaUIThemeColors.lunaDefaultDark`;
- component token groups for editor, gutter, minimap, scrollbar, caret, selection, and current line;
- chrome, menu-bar, active-menu underline, tab-strip, and separator tokens;
- dropdown/menu row, shortcut, disabled, checked, submenu-arrow, and separator tokens;
- panel/overlay, prompt/text-field, quick-panel/list-row, and modal-control tokens;
- tab, sidebar, status-bar, diagnostic, focus/accent, disabled, and selection tokens;
- demo-only Luna blue theme and high-contrast proof theme to verify overrides;
- render-ready style snapshots in LunaUI for editor, chrome, menus, panels, fields, tabs, sidebar, status bar, and controls;
- no product-specific public API names in Luna library targets.

Visual reference:

```text
dark charcoal chrome
blue-gray editor area when a theme chooses it
compact menu rows
restrained hover/selection accent
subtle active top-menu underline
compact tab strip
thin status bar
low-noise panels
rectangular controls
right-aligned shortcuts
minimal submenu arrows
```

Demo requirement:

- demo can switch themes at runtime through app-supplied commands rather than hardcoded color paths;
- current demo exposes those commands through the command palette and menu bar so bare number keys remain available for editor text input;
- semantic widget, modal overlay, modal text, button states, HUD/status text, moving block, menu rows, editor selection, and background all pull from the active theme.

Tests required:

- theme tokens resolve;
- component visual styles derive from theme tokens;
- custom theme overrides menu/editor/text-field/status colors;
- semantic widget colors derive from custom control tokens;
- modal control style derives from panel/text-field/control tokens;
- no core widget requires hardcoded colors except explicit debug/missing-token fallback.

Definition of done:

- Luna public theme APIs are product-neutral;
- app/demo code can supply arbitrary exact hex values;
- visible demo surfaces prove active theme values drive rendering rather than hardcoded colors.

### Phase 2E.1 — Product-Neutral Theme API Cleanup

**Status:** complete.

Goal: correct the boundary mistake where a Moth palette was temporarily promoted into Luna public API names.

Scope:

- remove Moth-specific public names from `LunaTheme`, `LunaUIThemeColors`, and component color-set extensions;
- keep built-in Luna defaults product-neutral;
- keep product/demo palettes outside reusable library targets;
- make `LunaUITestApp` the only place where demo-only Moth palette names appear.

Architecture rule:

```text
Luna can render any application theme.
Moth may supply one of those themes.
Luna does not name itself after Moth.
```

Definition of done:

- library targets expose product-neutral API names;
- test app may still contain `MothDemoTheme` as a consumer-supplied fixture;
- docs distinguish reusable Luna themes from application-supplied Moth themes.

### Phase 2E.2 — Renderer Color Contract and Demo Palette Proof

**Status:** complete.

Goal: make hex-driven theming visually trustworthy by locking the conversion from logical Luna colors to host framebuffer pixels.

Scope:

- define the practical color path from `LunaColor` logical RGBA to Luna framebuffer bytes to SDL texture upload;
- guard against byte-order mistakes where alpha can be interpreted as blue;
- document that hex parsing alone is not enough: the renderer/presenter path must preserve channels;
- demo-only Moth Obsidian palette in `LunaUITestApp`:
  - window/background: `#070709`;
  - button/control graphite: `#131416`;
  - dark gray layer: `#242426`;
  - light gray text: `#888991`;
  - text highlight: `#003CFF`.

Color contract:

```text
LunaColor.hex("#070709FF") means logical RGBA:
  R = 07
  G = 07
  B = 09
  A = FF

That must display as near-black, not bright blue.
```

Demo requirement:

- running the Luna Demo Blue command visibly selects the loud blue proof theme;
- running the Moth Obsidian command visibly selects the black/graphite demo-only app-supplied theme;
- running the High Contrast Proof command visibly selects the high-contrast proof theme;
- bare `1` / `2` / `3` remain ordinary editable text after Phase 4B.2.

Tests required:

- framebuffer byte contract is covered by tests;
- low-level presentation path uses the SDL texture format matching Luna's byte stream;
- demo-only Moth palette keeps blue reserved for selection/focus/highlight rather than broad surface fills.

---

## Phase 3 — Accessible Text View

Phase 3 should not begin until Phase 2D/2D.1/2D.2/2D.3 and Phase 2E are complete. Those gates are now complete; Phase 3A can build the first static, resize-safe, theme-driven, accessibility-aware Luna text-view primitive.

### Phase 3A — Static Accessible Text View

**Status:** complete.

Goal: establish the first editor-shaped Luna widget before editing exists.

Scope completed:

- `LunaStaticTextDocument`;
- stable plain-text line model;
- UTF-8 byte ranges for lines;
- `LunaStaticTextView` widget;
- editor background from theme tokens;
- gutter background from theme tokens;
- current-line row paint geometry from theme tokens;
- gutter/text viewport layout;
- bounded visible line text using Luna's debug-font metrics;
- accessibility text-area root node;
- visible text-run accessibility children;
- line hit testing through stable line node IDs;
- LunaUITestApp static editor-surface proof.

Explicit non-goals for Phase 3A:

- no editable input yet;
- no real caret yet;
- no mutable selection yet;
- no scrollbars yet;
- no syntax highlighting yet;
- no HarfBuzz glyph-run display-list command yet.

Definition of done:

```text
static text layout -> draw bounds -> hit-test bounds -> accessibility ranges
```

### Phase 3B — Caret Geometry and Static Selection Model

**Status:** complete.

Goal: add non-editable caret and selection geometry on top of the Phase 3A text surface before mutation/input policy exists.

Scope completed:

- `LunaTextLocation`;
- `LunaTextRange`;
- `LunaStaticTextCaret`;
- `LunaStaticTextSelection`;
- `LunaStaticTextSelectionRect`;
- `LunaStaticTextHitResult`;
- caret rectangle calculation from line/UTF-8 column;
- current line derived from caret when a caret exists;
- static selection range model with normalized document order;
- clipped selection rectangles across one or more visible lines;
- click-to-text-position hit calculation without mutating document text;
- accessibility caret range, selected range, and focused visible line proof.

Demo requirement completed:

- demo shows a caret and static selection highlight inside the Phase 3A text view;
- clicking a visible line moves the caret UI state and reports the computed text position without editing the document.

Tests completed:

- text locations clamp and map to absolute UTF-8 offsets;
- caret rect is correct for line/column;
- current line follows caret position;
- selection rects clip to visible line bounds;
- multi-line selections produce one rect per visible touched line;
- hit testing can map points to line/column positions;
- display list uses theme selection/caret tokens;
- accessibility exposes caret range, selected range, and focused line state.

### Phase 3C — Text View Scroll and Viewport

**Status:** complete.

Goal: prepare the read-only text surface for real editor usage by making the viewport explicit and scrollable before editable mutation exists.

Scope completed:

- `LunaStaticTextScrollState`;
- logical-line scroll offset;
- visible line range value;
- content height;
- max scroll-top-line calculation;
- scrollbar/minimap lane placeholder geometry;
- theme-driven scrollbar track/thumb display-list commands;
- hit testing with scroll offset;
- accessibility visible text range;
- demo keyboard scrolling with Up/Down/PageUp/PageDown/Home/End.

Demo requirement completed:

- long demo text scrolls;
- caret and hit testing respect scroll position;
- Moth Obsidian / Luna demo / high-contrast themes still flow through text-view colors.

Tests completed:

- scroll-state clamping and logical scroll deltas;
- ensure-visible scroll positioning for caret locations;
- content height and visible line range;
- scrollbar lane/thumb geometry;
- scrolled hit testing;
- offscreen caret/selection clipping;
- accessibility visible text range;
- display-list scrollbar theme tokens.

### Phase 3D — Editable Text Input Foundation

**Status:** complete.

Goal: start controlled text mutation on top of the Phase 3A/3B/3C text-view foundation without pulling command palette, file I/O, or Moth app policy into Luna.

Scope completed:

- `LunaEditableTextDocument`;
- `LunaEditableTextState`;
- `LunaTextEditResult`;
- insertion at caret;
- newline insertion;
- backspace/delete around caret;
- selection replacement;
- caret update after mutation;
- left/right caret movement across line boundaries;
- viewport ensure-visible after mutation in the demo;
- platform-neutral committed text-input event type;
- SDL text-input event translation in the host layer;
- editable accessibility metadata on text-area nodes;
- LunaUITestApp editable text proof.

Explicit non-goals for Phase 3D:

- no syntax highlighting;
- no undo stack yet;
- no clipboard;
- no IME composition model beyond committed text events;
- no file save/load;
- no command palette;
- no Moth application shell.

---

## Phase 4 — Sublime/Moth UI Surfaces

### Phase 4A — Command Palette / Quick Panel

Status: complete.

Implemented:

- generic `LunaQuickPanelItem` and command-descriptor item bridge;
- deterministic query filtering and ranking;
- quick-panel state with query text and selected row;
- quick-panel overlay layout;
- selected row rendering through theme/menu tokens;
- keyboard navigation with Up/Down/PageUp/PageDown/Home/End;
- Backspace query editing;
- Enter activation and Escape close;
- pointer row activation;
- accessibility dialog, editable query field, list, and list-item nodes;
- demo command palette opened with Ctrl+P.

Visual target: Sublime command palette and Goto Anything references.

### Phase 4A.1 — LunaUITestApp Demo Layout Cleanup

**Status:** complete.

This is intentionally a demo/test-app composition pass, not a Luna public API expansion. As the demo accumulated proofs from Phases 1–4A, the editor surface, moving block, semantic widget, HUD text, status text, modal overlay, and quick panel started visually competing.

Implemented cleanup:

- stable header strip for demo title, current theme, frame/time, and key help;
- main editor surface kept clear of normal HUD/status/debug text;
- right-side proof panel for the semantic widget and moving animation on wide windows;
- bottom status bar for interaction status, caret line/column, scroll position, and edit revision;
- moving animation constrained to the proof panel instead of crossing the editor;
- responsive fallback for narrow windows.

Hard rule preserved:

```text
LunaUITestApp can be a product-specific visual playground, but Luna library APIs stay product-neutral.
```

### Phase 4B — Generic Find / Replace Panel Foundation

**Status:** complete.

Implemented:

- product-neutral `LunaFindQuery`, `LunaFindOptions`, `LunaFindMatch`, and `LunaFindResultSet`;
- deterministic literal scanning with case-sensitive and whole-word options;
- Foundation-backed regex scanning for the initial regex toggle path;
- `LunaFindPanelState` with query text, replace text, focused field, options, and selected match;
- keyboard interaction for Escape, Tab, Backspace, Enter, and Shift+Enter;
- replace-current and replace-all controller operations over `LunaEditableTextState`;
- generic app-supplied text-view highlight ranges so find results are not special-cased as selections;
- bottom find/replace panel layout with query/replace fields, option toggles, previous/next, replace, and replace-all buttons;
- theme-driven panel, field, button, and highlight colors;
- accessibility dialog, editable fields, status, buttons, and toggle buttons;
- `LunaUITestApp` demo opened with Ctrl+F while keeping any Moth-specific demo language outside Luna's public API.

Visual target: Sublime find and find/replace references, implemented as reusable Luna primitives.

### Phase 4B.1 — Interactive Text Selection Completion

**Status:** complete.

This is a backfill/correctness phase discovered during the Phase 4B audit. Phase 3B supplied the text coordinate, caret, and selection-rectangle model, but the demo/editor interaction layer still behaved like a caret-only surface. Phase 4B.1 finishes the expected editor behavior before Luna moves on to menus.

Implemented:

- `LunaPointerEvent` carries platform-neutral keyboard modifiers for Shift-click style gestures;
- SDL pointer events populate those modifiers inside `LunaHostSDL` so SDL modifier details stay below LunaInput;
- editable text state can begin, set, extend, collapse, and clear directional selections;
- Shift+Left and Shift+Right extend selections from the current caret/anchor;
- plain Left/Right collapse existing selections to their normalized start/end;
- click-drag in `LunaUITestApp` creates real user text selections;
- Shift-click extends from the current caret/selection anchor;
- typing, Backspace, and Delete replace/delete the active user selection through the existing editable document contract;
- user selection remains visually separate from current-line highlight and find-result highlights.

Hard distinction preserved:

```text
current line highlight != user text selection != find result highlight
```

### Phase 4B.2 — Demo Command Routing and Text Input Focus Cleanup

Status: complete.

Phase 4B.2 tightened LunaUITestApp input ownership after editable text, command palette, find/replace, and interactive selection all became active at once.

It retired the demo-only bare `1` / `2` / `3` theme hotkeys so numbers can be typed into the editor as normal text. Theme switching now happens through command-palette commands supplied by the demo app.

It also adds Select All behavior through `Ctrl+A` and a command-palette command, using a product-neutral editable text selection primitive rather than test-app-specific range math.

Acceptance rules:

```text
bare 1/2/3 insert editor text
Ctrl+P owns palette input
Ctrl+F owns find-panel input
Ctrl+A selects the full editor document
command-palette theme commands remain the only demo theme-switching path
```

## Phase 4C — Menu Bar and Dropdown Menus

Status: complete.

Phase 4C adds the reusable product-neutral menu foundation. Luna owns menu state, layout, hit testing, accessibility, pointer/keyboard navigation, and theme-driven row geometry; applications supply menus and command handlers.

Completed scope:

- top menu bar;
- dropdown rows;
- first-pass submenus;
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

Phase 4C demo proof:

```text
click top-level menu -> dropdown opens
hover rows -> highlighted row changes
click command row -> command runs through existing demo command dispatch
click disabled row -> menu consumes but does not activate
keyboard arrows navigate top-level menus, rows, and first-pass submenus
Enter/Space activates the highlighted command
Escape dismisses menus
visible labels render for top-level menus and dropdown rows
shortcut labels render in the aligned shortcut column
Theme menu check marks follow the active demo theme
```

### Phase 4D — Tabs / Sidebar / Status Bar Shell

Status: complete.

Phase 4D pulls the editor chrome shell forward from the old Phase 5 outline because the demo/editor surface now needs a stable frame before context menus, completion popups, minimap, and real application documents are layered in. Luna owns product-neutral shell model/state/layout/hit testing/accessibility; applications supply actual tabs, project/sidebar data, status values, and command handlers.

Completed scope:

- reusable `LunaEditorShell` primitive;
- product-neutral tab IDs and tab model with active/hover/dirty/pinned/closable states;
- product-neutral sidebar item IDs and tree/list model with expandable folders, selection, hover, and visible-row flattening;
- product-neutral status-bar segment model with leading/trailing placement, normal/muted/accent emphasis, and optional command dispatch;
- shell layout that produces tab-strip, sidebar, editor-content, and status-bar frames from one bounds source;
- pointer routing for tab activation, close buttons, sidebar disclosure toggles, sidebar selection, and clickable status segments;
- theme-driven display-list geometry for tabs, sidebar rows, editor content background, and status bar;
- accessibility nodes for tab strip, tabs, close buttons, sidebar list/rows, status bar, and status segments;
- demo integration that frames the editable text view with visible tabs, sidebar, and dynamic status segments.

Phase 4D demo proof:

```text
tabs are visible above the editor content
active/dirty/closable tab states are visible
sidebar tree rows are visible and expandable
clicking disclosure arrows expands/collapses rows
clicking a sidebar file selects it and routes a command
status bar segments show status, revision, syntax, scroll, and caret position
editor text hit testing still works inside the shell content frame
menus/palette/find/modal overlays retain input ownership above the shell
```

### Phase 4E — Context Menu

Status: complete.

Phase 4E adds product-neutral floating context-menu infrastructure on top of the Phase 4C menu item/dropdown-row model. Luna owns context menu definition shape, open/close state, anchored layout, bounds clamping, hit testing, pointer/keyboard routing, theme-driven dropdown geometry, and accessibility semantics. Applications own which menu appears for a given surface and what commands do.

Completed scope:

- reusable `LunaContextMenuDefinition`, `LunaContextMenuState`, `LunaContextMenuLayout`, and `LunaContextMenu` primitives;
- right-click / secondary-click opening from demo editor text/content, tabs, sidebar rows, and status-bar segments;
- reuse of `LunaMenuItem`, `LunaMenuItemPath`, `LunaMenuRowFrame`, `LunaMenuDropdownFrame`, and menu shortcut display formatting;
- compact floating dropdown rows with separators, disabled states, checked states, shortcut display, and first-pass submenus;
- viewport clamping so context menus do not render off-screen at window edges;
- pointer routing for hover, disabled-row consumption, command activation, submenu opening, outside-click dismissal, and secondary-button interaction;
- keyboard routing for Escape, Up/Down, Left/Right submenu traversal, Enter, and Space;
- accessibility root menu and menuitem nodes, focused row state, disabled state, checked labels, shortcut/submenu values, and press/focus actions;
- demo command dispatch for editor paste/select/find, tab/sidebar/status contexts, theme submenu checks, and context-menu info notices.

Phase 4E demo proof:

```text
right-click editor -> editor context menu
right-click tab -> tab context menu
right-click sidebar row -> sidebar context menu
right-click status segment -> status context menu
hover/click/keyboard navigation work on each menu
outside click and Escape dismiss without leaking input underneath
Theme submenu check marks follow the active demo theme
```

### Phase 4F — Completion Popup

Status: complete.

Phase 4F adds a product-neutral anchored completion surface. Luna owns completion item/state shape, anchor-relative layout, viewport clamping, selected-row behavior, keyboard/pointer routing, theme-driven popup geometry, and accessibility semantics. Applications own completion sources, filtering/ranking policy, insertion behavior, and document/language semantics.

Completed scope:

- reusable `LunaCompletionItem`, `LunaCompletionPopupState`, `LunaCompletionPopupLayout`, and `LunaCompletionPopup` primitives;
- app-supplied anchor rectangle, demonstrated from the editable text caret;
- below/above placement and viewport-edge clamping;
- selected rows with optional annotation and detail text;
- keyboard navigation for Up/Down, PageUp/PageDown, Home/End, Escape, Enter, and Tab;
- pointer hover, pointer activation, disabled-row consumption, and outside-click dismissal;
- completion result payloads carrying selected item, optional command ID, and insertion text without mutating documents inside LunaUI;
- accessibility list/list-item/status nodes with focused row state and press/focus actions;
- demo integration through `Ctrl+Space`, menu/context-menu commands, and static app-owned suggestions.

Phase 4F demo proof:

```text
Ctrl+Space -> completion popup opens near the caret
Up/Down/Page/Home/End navigate suggestions
Enter/Tab inserts the selected suggestion or routes its command
Escape and outside click dismiss
Typing normal text after the popup closes still edits the document
visible row titles, annotations, and detail text come from theme-aware bounded layout
```

---

## Phase 5 — Editor Surface Deepening

The original Phase 5 chrome-shell outline has been pulled forward into Phase 4C/4D/4E/4F: menu bar, tabs, sidebar, status-bar, context-menu, and completion-popup primitives now exist as reusable LunaUI surfaces. Phase 5 is now the deeper editor/content pass that can rely on that shell.

### Phase 5A — Real Document / Buffer Integration

Status: complete.

Phase 5A moves the demo/editor surface from a single global editable text fixture to product-neutral open-document/buffer identity. Luna owns descriptor/store shapes, active-document routing, dirty-state derivation, and shell-tab projection helpers. Applications still own file I/O, project policy, save policy, and real Moth Text behavior.

Completed scope:

- reusable `LunaDocumentID`, `LunaDocumentDescriptor`, `LunaDocumentBuffer`, and `LunaDocumentStore` primitives;
- open-buffer storage around the existing `LunaEditableTextState` mutation foundation;
- per-document caret, selection, edit revision, and logical scroll preservation;
- dirty/modified state derived from editable text revisions rather than static demo tab flags;
- document-to-shell tab projection with app-supplied activate/close commands;
- active document synchronization into `LunaEditorShellState` tab and sidebar selection;
- document-aware status segments for active title, dirty/saved state, syntax, revision, scroll, and caret location;
- demo tabs/sidebar rows that switch the actual editor text buffer while preserving input ownership rules from Phase 4.

Phase 5A demo proof:

```text
click tab -> active document changes
editor text swaps to that document buffer
type -> active document becomes dirty and tab/status update
switch away/back -> document-local text, caret/selection, and scroll are preserved
sidebar open-document rows activate the same document IDs
find/replace/completion/context/menu operations target the active document
```

### Phase 5B — Product-Neutral Editor Command Runtime

Status: complete.

Phase 5B turns the earlier command descriptors into an actual runtime path that Moth can later use across menus, context menus, the command palette, keyboard shortcuts, accessibility actions, and future toolbar/status actions. Luna owns descriptors, availability projection, key binding matching, and execution plumbing; applications own command handlers and product policy.

Completed scope:

- `LunaCommandContext` for focused surface, active document ID, source, and simple execution attributes;
- `LunaCommandAvailability` for dynamic enabled, visible, checked, title override, and disabled-reason state;
- `LunaCommandExecutionResult` for handled/unhandled status, announcements, and follow-up command hooks;
- `LunaKeyStroke`, `LunaKeyBinding`, and `LunaKeyBindingMap` for product-neutral shortcut matching;
- compatibility matching for legacy display strings like `Ctrl+P` while preferring explicit key/modifier descriptors;
- `LunaCommandSurfaceItem` for menu/palette/context/status projection;
- generic `LunaCommandRuntime<Host>` that executes handlers against an app-owned mutable host;
- LunaUI keyboard-event adapters that translate `LunaKeyboardEvent`/modifiers into command key strokes;
- demo key shortcuts, command palette, menu rows, and context menu rows now resolve through the same runtime-backed command state/execution path.

Phase 5B demo proof:

```text
Ctrl+A, Edit > Select All, Selection > Select All, context menu > Select All, and command palette > Select All route through one command ID
Ctrl+P, Ctrl+F, and Ctrl+Space route through the command keymap rather than ad-hoc shortcut checks
disabled/checked menu and context rows are resolved from command availability
theme/sidebar/tab checked states come from command runtime surface projection
command handlers still live in LunaUITestApp, proving Luna owns machinery but not product policy
```

### Phase 5C — File / Project Adapter Boundary

Status: complete.

Phase 5C builds the product-neutral seam between Luna editor/document surfaces and application-owned file/project policy. Luna still does not perform real filesystem I/O, choose save prompts, walk project folders, filter ignored files, or become Moth Text. It owns the descriptor/request/result shapes and projection helpers that a product adapter can feed.

Completed scope:

- `LunaFileID`, `LunaProjectID`, and `LunaWorkspaceNodeID` typed identities;
- `LunaFileReference`, `LunaFileDescriptor`, and `LunaProjectDescriptor` metadata models;
- `LunaProjectTreeNode` and `LunaProjectTreeSnapshot` for project/sidebar data snapshots;
- project-tree to `LunaSidebarItem` projection helpers with app-owned command generation;
- `LunaWorkspaceState` for known files, open file IDs, active file ID, selected node, and expanded node state;
- `LunaWorkspaceAdapter` protocol shape with open-file, save-document, and project-tree snapshot operations;
- `LunaWorkspaceOpenRequest`/`LunaWorkspaceOpenResult`;
- `LunaDocumentSaveRequest`/`LunaDocumentSaveResult`;
- dirty-document close request/resolution/policy models;
- document-store helpers for opening/activating file descriptors, save requests, save-result application, dirty IDs, and close requests;
- demo integration using an in-memory workspace adapter so sidebar rows can open file-backed document buffers and Save/Save All can clear dirty state through the adapter boundary.

Phase 5C demo proof:

```text
sidebar tree comes from LunaProjectTreeSnapshot projection
clicking a workspace file row opens or activates a document through LunaWorkspaceAdapter
File > Save clears active dirty state through LunaDocumentSaveRequest/Result
File > Save All clears all dirty demo documents through the same adapter seam
File > Close Document consults dirty-close policy before closing
status bar includes project/workspace metadata without Luna owning project policy
```

### Phase 5C.1 — Frame Pacing, Invalidation, and Runtime Boundary

Status: complete.

Phase 5C.1 hardens the host/runtime boundary before real file I/O and future async services. It does not make widgets concurrent, does not turn document state into an actor, and does not parallelize the renderer. It defines how a host requests frames, records timing, avoids needless redraws, and keeps all Luna UI state mutation on one deterministic UI lane.

Completed scope:

- `LunaInvalidationReason` for input, text, document, overlay, command, theme, workspace, resize, animation, async-result, accessibility, and explicit invalidations;
- `LunaFrameInvalidationSet` for collecting render reasons;
- `LunaFrameRequest` for deciding whether a frame should be rendered;
- `LunaFrameTimingSample` and `LunaFrameTimingStats` for host-side measurement of frame, render, and present cost;
- `LunaFramePacer` for deciding whether the host or external vsync owns pacing;
- `LunaAnimationClock` and `LunaAnimationFrame` for host-owned logical animation timing with large-delta clamping;
- `LunaRuntimeTick` for future bounded periodic work and async-result polling;
- Linux SDL presenter can now be created with or without vsync and exposes whether vsync is active;
- Linux demo loop no longer unconditionally double-throttles with both vsync and `SDL_Delay(16)`;
- Linux demo loop renders only when invalidated or when a scene explicitly requests continuous frames;
- demo status bar reports frame timing and latest invalidation reasons;
- host-runtime tests cover invalidation, frame requests, timing stats, frame pacing, and runtime ticks.

Architecture rule:

```text
Luna widgets remain synchronous and deterministic.
Host runtimes own frame pacing and invalidation scheduling.
Applications/services may do async work, but async results return to the UI lane as snapshots/events before mutating Luna state.
```

### Phase 5C.2 — Editor Harness Split and Input Coalescing

Status: complete.

Phase 5C.2 originally separated the default LunaUITestApp from the older proof-gallery/stress surfaces so a small Moth-like editor harness could be measured independently. C2.3 keeps that lean harness behind explicit `--editor` selection but restores the complete kitchen-sink presentation as the default user-facing demo.

Completed scope:

- `LunaDemoMode.editor` as the original Phase 5C.2 default run mode, superseded by C2.3 kitchen-sink defaulting;
- `LunaDemoMode.proofGallery` selectable with `--proof-gallery`, `--proof`, or `LUNA_DEMO_MODE=proof`;
- editor-mode layout gives the editor surface the shell content area instead of reserving side proof-panel space;
- proof panel, moving block, semantic-widget proof, and HUD are visible in the default C2.3 kitchen-sink mode; `--editor` hides them for performance measurements;
- `LunaHostInputCoalescer` coalesces contiguous pointer-motion runs to the latest event while preserving button, key, text, resize, and quit boundaries;
- Linux host loop uses coalesced input batches and exposes coalesced-event diagnostics to the status bar;
- pointer redraw invalidation is based on meaningful state changes/commands/non-motion phases rather than mere geometric hits;
- command-request stdout spam is behind `LUNA_DEMO_DEBUG_COMMANDS=1` or `--debug-commands`;
- `LunaPointerActivationResult` carries `didChangeVisualState` so hosts can request redraws without confusing hit testing with invalidation;
- tests cover pointer-motion coalescing and preservation of semantic input boundaries.

Architecture rule:

```text
Luna remains state-driven and deterministic.
The explicit `--editor` mode is the lean performance harness.
Kitchen-sink and proof-gallery modes stay first-class for visual/stress regression coverage.
Pointer motion and adjacent committed text can be coalesced; semantic ordering barriers cannot be dropped.
```

### Phase 5C.2.1 — Targeted Tab / Document Close Routing

Status: complete.

Phase 5C.2.1 wires the tab strip close affordance and tab context-menu close command into the document/workspace close policy added in Phase 5C. It keeps `luna.demo.tab.close` generic and product-neutral by carrying the clicked tab/document as command-context metadata rather than minting one command ID per document.

Completed scope:

- `LunaCommandContextAttributeKey.targetDocumentID` and related target metadata keys;
- `LunaCommandContext.targetOrActiveDocumentID` fallback helper so command handlers can prefer explicit targets while still supporting active-document commands;
- `LunaContextMenuDefinition.commandContextAttributes` so context menus can preserve the source tab/document that opened them;
- tab close-button clicks pass the clicked `LunaShellTabID` as a target document to the generic close command;
- tab context-menu Close Tab carries the right-clicked tab as command context for pointer and keyboard activation;
- File > Close Document still closes the active document because it has no explicit target;
- tab close and File > Close Document both reuse `LunaDirtyDocumentClosePolicy` instead of mutating tab arrays directly;
- closing a clean document updates `LunaDocumentStore`, `LunaWorkspaceState.openFileIDs`, active document selection, sidebar selection, and shell active tab state;
- dirty close still reports the save-prompt decision until a real Save / Discard / Cancel modal is implemented;
- tests cover command-context target fallback, context-menu command attributes, and workspace state synchronization when the document store becomes empty.

Architecture rule:

```text
Tab close is document policy, not tab-strip paint policy.
The shell emits the target tab/document; the app command handler decides whether close is allowed.
Dirty documents still require a product/app prompt before destructive close behavior.
```

### Phase 5C.2.2 — MPL-2.0 License Migration

Status: **complete**.

Phase 5C.2.2 locks the project licensing baseline before real file I/O and broader public reuse work. The repository now uses the Mozilla Public License 2.0 (`MPL-2.0`), with the full license text in `LICENSE` and concise SPDX license identifiers at the top of package, source, test, C shim, and module-map files.

This phase is intentionally legal/project-infrastructure only. It does not change Luna runtime behavior, widget architecture, rendering, input routing, or workspace policy.

Phase 5C.2.2 deliverables:

- replace the previous license file with full MPL-2.0 text;
- add `SPDX-License-Identifier: MPL-2.0` headers to package/source/test/shim/module-map files;
- remove remaining project references to the old license;
- update README/current-status/demo-protocol/roadmap documentation;
- keep the next technical milestone, Phase 5D real file I/O, unchanged.

### Phase 5D — Real File I/O Proof

Status: **complete**.

Phase 5D proves the file/workspace adapter boundary with real local text files while keeping filesystem policy in the demo app target. `LunaUITestApp` now has an app-owned local-file adapter that can register `--open` launch paths, project them under a `Local Files` sidebar root, read UTF-8 contents into `LunaDocumentStore`, save active or dirty documents back through `LunaDocumentSaveResult`, and report read/write errors as status messages instead of making LunaUI own filesystem behavior.

Phase 5D deliverables:

- provide a narrow app-owned local-file adapter behind the Phase 5C contracts;
- parse launch paths through `--open path`, positional file paths, and `LUNA_DEMO_OPEN_FILE` / `LUNA_DEMO_OPEN_FILES`;
- open real UTF-8 text files into `LunaDocumentStore`;
- project opened local files into the sidebar as app-owned workspace nodes;
- save active and dirty documents back through adapter results;
- surface file errors as command execution status/status-bar text instead of crashing;
- keep LunaUI free of Moth-specific project policy, preferences, file dialogs, filesystem scanning, and UI prompts.

### Phase 5D.1 — Public-Domain Demo Corpus Integration

Status: **complete**.

Phase 5D.1 makes the Phase 5D real-file proof repeatable by checking in a small public-domain UTF-8 demo corpus under `Examples/PublicDomainDemoFiles`. The corpus contains Frankenstein and De Bello Gallico excerpts plus a manifest with byte counts and SHA-256 hashes. It is intentionally fixture/demo material, not a LunaUI source-code dependency and not a Moth product policy layer.

Phase 5D.1 deliverables:

- add the public-domain fixture corpus under `Examples/PublicDomainDemoFiles`;
- keep source/public-domain notes with the corpus so its provenance is clear;
- add `scripts/verify-public-domain-demo-files.py` to validate manifest entries, byte counts, and checksums;
- add `scripts/run-demo-corpus.sh` to verify and launch the editor harness against selected fixtures;
- add `--open-demo-corpus=largest|frankenstein|caesar|all` and `LUNA_DEMO_OPEN_CORPUS` convenience expansion in `LunaUITestApp`;
- add regression coverage proving the corpus is present, UTF-8 readable, and documented;
- update README, current status, demo protocol, Luna roadmap, and Moth roadmap.

### Phase 5D.2 — New File / Untitled Buffer / Save As Proof

Phase 5D.2 completes the basic editor file lifecycle in the default demo harness. It adds app-owned untitled buffers for File > New File / Ctrl+N, safe empty local-file creation through `--create`, demo Save As routing, and no-overwrite defaults while keeping LunaUI limited to neutral document descriptors, workspace state, and save/open request/result seams.

Phase 5D.2 deliverables:

- add File > New File and Ctrl+N routing to a demo-owned untitled document creator;
- add `--new-untitled` / `LUNA_DEMO_NEW_UNTITLED` launch support for repeatable untitled-buffer testing;
- add `--create path` / `LUNA_DEMO_CREATE_FILE(S)` support that creates empty UTF-8 local files safely and opens them through the Phase 5D adapter;
- add explicit overwrite flags for create/save-as testing without allowing accidental overwrite by default;
- add demo Save As routing with `--save-as` / `LUNA_DEMO_SAVE_AS_PATH` and generated `/tmp/luna-ui-save-as` fallback paths;
- keep all filesystem path policy in `LunaUITestApp`, not `LunaUI`;
- add regression coverage for untitled save requests, save-as identity migration, and workspace sync when the active document has no file descriptor;
- update README, current status, demo protocol, and Moth Text roadmap.

### Phase 5D.3 — Host Dialog Boundary for Native Open / Save / Dirty Close

Phase 5D.3 makes the editor demo behave like a desktop editor without moving OS dialog policy into LunaUI. LunaHostCore now defines neutral dialog request/result types plus `LunaDialogService`, and the demo app injects a scripted/native service for Open…, Save As…, Save-on-untitled, and dirty-close Save / Don’t Save / Cancel decisions.

Phase 5D.3 deliverables:

- add `LunaDialogService`, unsaved-changes request/result types, and file-dialog request/result types to LunaHostCore;
- add a scripted dialog implementation for deterministic tests and CLI-driven demos;
- route File > Open… through the dialog service before opening the selected path with the existing Phase 5D adapter;
- route File > Save on untitled documents and File > Save As… through the dialog service before saving through the app-owned local-file adapter;
- route dirty tab/document close through Save / Don’t Save / Cancel decisions, preserving user edits on cancel or unavailable dialog services;
- add a Linux/macOS demo helper bridge outside LunaUI, with scripted/CLI fallbacks for headless or minimal desktop sessions;
- leave a deliberate Plan-B seam so future Luna-rendered file-management widgets can satisfy `LunaDialogService` without making LunaUI own OS file-picker policy.

### Phase 5D.3.1 — Proof Gallery Animation Pacing

Status: **complete**.

At the Phase 5D.3.1 checkpoint, the proof-gallery-only animation roughness was fixed without changing the then-default editor harness into a continuously redrawn proof collage. C2.3 later restored the cached kitchen-sink mode as the user-facing default. LunaHostCore now exposes a small `LunaAnimationClock`/`LunaAnimationFrame` primitive for host/demo animation timing. The proof-gallery moving square advances from clamped logical animation time, so modal dialogs, debugger pauses, event backlog, or host scheduling stalls do not cause a large position jump on the next frame.

Phase 5D.3.1 deliverables:

- add a host-runtime animation clock with default delta, maximum delta, elapsed phase, latest-frame diagnostics, and reset support;
- use that clock for the proof-gallery moving block instead of raw process uptime;
- report animation delta/phase in proof-gallery status/HUD diagnostics;
- mark continuous proof-gallery frames with the `animation` invalidation reason;
- keep the editor mode event/invalidation driven and free of proof-gallery animation surfaces;
- remove duplicate demo-chrome drawing from the shared CPU renderer;
- add regression coverage for first-frame delta, stall clamping, and reset behavior.

### Phase 5D.3.2 — Proof Gallery Static Frame Cache

Status: **complete**.

Phase 5D.3.2 fixes the remaining proof-gallery-only animation sluggishness by separating static proof-gallery rendering from animation-only rendering. The proof gallery remains the stress/regression harness, but the moving-square proof no longer forces the full editor shell, sidebar, status text, menu bar, proof panel chrome, semantic proof widget, and text viewport to be rebuilt every vsync when the only invalidation is animation.

Phase 5D.3.2 deliverables:

- add an explicit `LunaFramebuffer.copyPixels(from:)` full-frame copy helper so cached frames can be restored without relying on Swift Array copy-on-write timing;
- remove Mirror/reflection from the raw framebuffer upload helper used by host presenters;
- add a demo-owned static proof-gallery framebuffer cache;
- use the cache only for animation-only frames with no active transient overlays;
- redraw only the moving proof square and small HUD diagnostics on animation-only frames;
- refresh the cache on normal invalidations such as input, document edits, theme changes, workspace changes, overlays, and resize;
- keep the editor mode event/invalidation driven;
- add regression coverage for raw framebuffer byte-count access and full-buffer pixel copying.

### Phase 5E — Layered Component Boundary and Moth Extraction Seams

Status: **complete through Phase 5E.2**.

Purpose: formalize the new Luna family-of-libraries paradigm before additional editor-shell behavior hardens accidental monolithic APIs.

This is an extraction and contract phase, not a rewrite. All current demo features and performance behavior must remain working.

Scope:

- classify current `LunaUI` types as foundation/general UI, optional document/editor component, or Moth-policy risk;
- document and test the dependency direction defined in `docs/LUNA_LAYERED_ARCHITECTURE.md`;
- separate generic find/search panel presentation from document scanning, replacement policy, and editor undo integration;
- explicitly scope `LunaEditableTextDocument` as a lightweight reusable text model rather than the future Moth production source buffer;
- establish generic text-storage/document-view protocols where they reduce coupling without speculative abstraction;
- prove buffer-versus-view separation so two editor views can share a document while retaining independent caret/selection/scroll state;
- rename or narrow editor-shell APIs whose names or state imply Moth product policy;
- identify future optional SwiftPM target cuts such as `LunaTextEditing`, `LunaDocumentUI`, and `LunaEditorComponents`, without requiring all physical moves in one commit;
- add architecture tests preventing Luna foundation/general UI from depending on Moth/product layers;
- preserve the explicit editor harness, default kitchen-sink demo, proof-gallery compatibility mode, file I/O proof, dialogs, and frame-cache performance baseline.

Definition of done:

- no current feature is deleted merely for being editor-adjacent;
- reusable editor anatomy has a documented optional Luna home;
- Moth-owned semantics are named and isolated behind seams;
- one buffer can back two independent view states in tests;
- find-panel UI can operate against an injected provider/session rather than owning product search policy;
- the next tab/split work has an agreed target layer and does not deepen `LunaUI` monolith coupling.

### Phase 5F — Tab Overflow, Pinned Tabs, and Split/Panes

Status: **Phase 5F.1, Phase 5F.2A, Convergence C1A, C1B, C2, and C2.1 complete in this revision.**

Phase 5F.1 delivered:

- recursive product-neutral pane and split identities;
- horizontal/vertical layout and divider geometry;
- active-pane state, wrapping traversal, and directional traversal by visual geometry;
- split insertion, removal/collapse, and bounded divider resizing;
- product-neutral command context projection for active and target panes;
- pinned-tab compact layout, active-tab visibility, hidden-tab reporting, and reusable overflow presentation state;
- host termination veto support so product dirty-document policy can cancel native window close;
- regression tests and a LunaUITestApp split-pane proof.

Phase 5F.2A and convergence delivered:

- pane content frames and independent pane-bound text surfaces;
- width-correct soft wrapping and visual-row scrolling;
- native text/resize cursor intent and captured divider dragging;
- reusable click/Shift-click/drag, Unicode word/line selection, and edge autoscroll;
- immediate downstream consumption by Moth without transferring document or view ownership;
- C2 validation that production Undo/Redo, grouping, dirty-state checkpoints, and view restoration remain Moth-owned.

Remaining later interaction scope:

- visible split commands and keyboard affordances;
- polished tab-overflow presentation;
- Moth-driven editor groups, cloned views, project persistence, and sessions;
- command/menu/find convergence only through product-neutral Luna presentation seams.

---

## Convergence C1A, C1B, C2, and C2.1 — Downstream Editor Interaction

**Status: complete.**

C1A added product-neutral cursor intent, native host cursor mapping, reliable pointer capture, and forgiving divider interaction. C1B extracted pointer-selection interpretation into a reusable Luna layer while leaving documents, selections, and mutation in applications.

C2 is an intentional source-freeze milestone for Luna. Moth implements document-owned Undo/Redo stacks, inverse edits, deterministic grouping, redo branching, multi-view restoration, and saved-history checkpoints entirely in its own modules. Luna's existing C1B public APIs are sufficient.

C2 architectural result:

```text
Luna owns reusable editor anatomy and input interpretation.
Moth owns history, grouping, dirty state, and editor meaning.
```

C2.1 graphical-correction result:

- `LunaDebugBitmapTextRenderer` remains an ASCII-only diagnostic tool;
- `LunaTextRender` is an optional reusable product for production CPU text painting;
- HarfBuzz cluster advances and FreeType glyph masks are cached per renderer/font;
- unsupported glyphs paint an explicit box instead of an invisible advanced cell;
- downstream monospaced editors can derive their cell advance from a shaped run so painting and caret/wrap geometry use one metric;
- application-specific dirty/active icons remain application-owned geometry.

C2.1 intentionally does not claim complete bidirectional layout, script segmentation, or multi-font fallback. Those remain later LunaText work.

M2.2B1 command-convergence result:

- Moth consumes Luna's existing command runtime, menu bar, and quick panel;
- Moth retains stable product command IDs, availability, file lifecycle, and editor policy;
- filtered quick panels keep matching disabled items discoverable instead of silently removing them;
- disabled metadata remains available to rendering and accessibility while the product reports the reason;
- a focused Phase 4A regression protects the reusable behavior.

No Luna production API is added merely to mirror Moth's product model. The small
M2.2B1 source correction repairs generic quick-panel filtering rather than adding
Moth-specific command meaning.

C2.2 exact-geometry and scrolling result:

- `LunaUnicodeTextLayout` exposes stable grapheme insertion boundaries in UTF-8 and HarfBuzz 26.6 coordinates;
- `LunaStaticTextRowGeometry` is the single horizontal geometry consumed by soft wrapping, caret placement, selection rectangles, and hit testing;
- fixed-cell geometry remains an explicit diagnostic fallback rather than the production Unicode coordinate source;
- `LunaHostInputEvent.scroll` carries platform-neutral two-axis deltas, precision, phase, location, and modifiers;
- LunaHostSDL translates conventional wheels and precise trackpad deltas without leaking SDL types above the host;
- `LunaStaticTextScrollInteraction` supplies deterministic visual-row wheel accumulation, scrollbar lane paging, and captured thumb dragging while products retain viewport ownership;
- full bidi, font fallback, and horizontal editor scrolling remain explicitly deferred.

C2.3 input-to-pixel latency and demo-restoration result:

- retained: plain printable SDL key-down events defer to authoritative committed text input while command-modified and special keys remain semantic events;
- retained: input-to-present timing and coalescing diagnostics;
- retained: default kitchen-sink presentation, moving-square proof, and deterministic 340-row scrolling corpus;
- retained: explicit `--editor` performance harness and `--proof-gallery` compatibility mode;
- rejected after native graphical acceptance: presenting after each bounded raw polling batch;
- architectural lesson: raw acquisition limits are safety boundaries only and may never define frame boundaries.

---

## Phase 6 — Renderer and Snapshot Correctness

This phase can happen partly in parallel, but it needs its own gates.

Scope:

- framebuffer coordinate contract;
- framebuffer color/channel-order contract;
- CPU renderer as reference;
- text orientation snapshot tests;
- display-list snapshot tests;
- color swatch/channel-order snapshot tests;
- dirty rect diagnostics;
- glyph bounds diagnostics;
- future GPU/Metal parity tests.

Important bugs to guard against:

- mirrored text;
- wrong origin;
- alpha/channel-order mistakes that turn black into blue;
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

## Convergence C2.4 — Interactive runtime and presentation scheduling

**Status: ordinary interaction scheduling accepted; scalability audit required.**

C2.3's demo restoration and diagnostics remain valid, but its stateless bounded
polling policy is rejected. C2.4 introduces a persistent semantic scheduler across
raw acquisition passes, makes clicks/commands ordering barriers, dispatches text by
idle state, threshold, or deadline, and makes presentation depend on visible scene
invalidation rather than native queue chunking. VSync and software pacing no
longer sleep while semantic input remains pending.

The focused scheduler suite contains nine regressions. The complete Luna test
inventory is 261 tests across XCTest and Swift Testing; native text-render tests
require real FreeType/HarfBuzz/font dependencies. Native validation accepted the
scheduler for ordinary Moth documents, but exposed non-virtualized whole-document
text layout and continuously composed demo frames as separate scalability failures.

Exit condition:

> Raw acquisition limits never cause intermediate frames. Clicks, commands,
> navigation, scrolling, and dialogs remain prompt under motion/text backlogs, and
> sustained text presents within the configured latency deadline without event
> loss or reordering.

Native result: this interaction-scheduling exit condition passed for the ordinary
Moth graphical shell. C2.4 does not claim large-document or animated-demo
performance acceptance.

## Post-C2.4 Native Scalability Findings

- the Luna kitchen-sink and proof-oriented demos remain sluggish under continuous animation;
- a generated roughly 500-line Moth document can freeze or become unusably slow;
- text layout currently creates complete-document visual segments before slicing the viewport;
- scrollbar-width resolution can repeat the complete soft-wrap pass;
- multiple panes and minimap consumers currently duplicate snapshot/layout work;
- the 128-entry shaped-layout cache is appropriate only after layout is virtualized and otherwise thrashes under eager whole-document traversal.

These are Critical A1 findings. They must not be hidden by raising cache limits,
reducing animation rate, or disabling the long test corpus.

## Immediate Next Implementation Target

```text
A1.1 measured large-document and demo-composition audit
```

Instrument operation counts and timings for snapshot projection, line indexing,
wrap planning, shaping, visible-row materialization, minimap projection,
framebuffer drawing/copying, and SDL presentation across 50, 500, 5,000, and
50,000 line fixtures. Publish Critical/High/Medium/Low/Accepted-Debt findings and
reconvene. C2.5 virtualized text layout and demo composition is only a candidate
until the audit confirms the design. M3A remains blocked.
