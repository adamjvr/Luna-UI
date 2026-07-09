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

### Phase 4D — Context Menu

Scope:

- right-click menu;
- compact rows;
- separators;
- disabled states;
- first-pass submenus;
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

## Immediate Next Implementation Target

The next implementation target is:

```text
Phase 4A — Command Palette / Quick Panel
```

Phase 3A, 3B, 3C, and 3D are complete. The next implementation target is the first Sublime-style command palette / quick panel surface layered on top of the modal, bounded text, theme, keyboard, and text-input foundation.
