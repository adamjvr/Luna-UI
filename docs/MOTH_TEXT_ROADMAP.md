# Moth Text Roadmap

Moth Text is the end-user editor product. Its long-term goal is to become a Swift-native, Sublime-class text editor with clean-room Sublime compatibility and additional modern features.

Moth Text is built on Luna UI. Luna owns the reusable custom UI/runtime layer, renderer, text shaping infrastructure, accessibility tree, overlay system, platform hosts, and theme primitives. Moth owns editor product behavior: documents, buffers, commands, projects, settings policy, packages, compatibility importers, user-facing editor workflow, and product-specific theme choices.

This split is the central design decision.

---

## Product Definition

Moth Text is:

- a modern Sublime-class code/text editor;
- written in Swift;
- built on Luna UI;
- custom-rendered through Luna rather than SwiftUI/AppKit widgets/Electron;
- Sublime-like in workflow and visual behavior;
- clean-room in implementation;
- accessibility-first through Luna’s semantic widget/text model.

Moth Text is not:

- the Luna UI engine;
- a Sublime Text fork;
- a port of Sublime internals;
- a generic IDE clone;
- a place for SDL, Metal, AppKit, HarfBuzz, FreeType, or platform accessibility imports to leak into editor product code.

---

## Relationship to Luna UI

```text
Luna UI owns:
  widgets, overlays, focus, layout, host input, accessibility, rendering, themes.

Moth Text owns:
  editor behavior, documents, commands, projects, settings, packages, compatibility.
```

Sublime-like UI surfaces should be implemented using Luna primitives:

```text
Command Palette      Luna quick panel + Moth command registry
Goto Anything        Luna quick panel + Moth project/file/symbol index
Find/Replace         Luna bottom panel + Moth find engine
Completion Popup     Luna anchored popup + Moth completion providers
Menus                Luna menu model + Moth command descriptors
Status Bar           Luna status widget + Moth status policy
Tabs/Splits          Luna layout widgets + Moth document/workspace model
Themes               LunaTheme + Moth/Sublime compatibility importers
Syntax               Moth syntax model + Luna text/render pipeline
Multiple Cursors     MothTextCore model + Luna text view rendering
Packages/Plugins     MothPackageKit, not Luna core
```

---

## Visual Goal

Moth Text should feel familiar to Sublime Text users.

The default Moth visual language should include:

- dark editor-first interface;
- compact tab/menu/status bar sizing;
- charcoal chrome and overlays;
- blue-gray editor area if the selected theme wants it;
- compact rectangular controls;
- restrained highlight/selection accents;
- thin borders and low-contrast separators;
- command palette and quick panels shaped like Sublime;
- bottom find/replace panels shaped like Sublime;
- menu dropdowns with Sublime functionality plus room for improved discovery/accessibility.

Moth must not be forced to use the Luna demo palette or any Luna built-in theme. Moth supplies its own exact Luna theme values, including hex-defined colors for editor, chrome, tabs, sidebar, overlays, menu rows, selections, status bar, minimap, and controls.

The current Moth visual palette being proven in `LunaUITestApp` is demo-only consumer code, not Luna public API:

```text
window/background black  #070709
button/control graphite  #131416
dark gray layer          #242426
light gray text          #888991
text highlight blue      #003CFF
```

In the future Moth repo, these values should live under Moth theme code or user theme files. Luna should only see them as a normal application-supplied `LunaTheme`.

---

# Implementation Phases

## Moth Phase 0 — Product Definition and Engine Boundary

**Status:** design target.

Goal: lock the product/engine split before app code starts.

Scope:

- Moth depends on Luna;
- Luna does not depend on Moth;
- Moth does not import platform host/rendering APIs for normal editor UI;
- Moth behavior is expressed through commands, documents, projects, settings, editor models, and product-owned theme choices.

Definition of done:

- Moth’s module boundaries are documented;
- Luna phases required before Moth bootstrap are identified;
- the first Moth app target can be created without duplicating Luna infrastructure.

---

## Moth Phase 1 — Text Core

Goal: build editor data models independent of UI.

Scope:

- `MothTextBuffer` protocol;
- first buffer implementation;
- line index;
- cursor model;
- multiple-selection foundation;
- edit transaction model;
- undo/redo manager;
- dirty state;
- command IDs for core editing actions;
- tests for basic text operations.

Important constraint:

- the first buffer may be pragmatic, but APIs must not assume Swift `String` indexing is the final large-file model;
- long-term target is rope, piece table, or another large-document-safe model.

Definition of done:

- edits are represented as transactions;
- selections and cursors are model-level concepts;
- UI code is not required to test editing behavior.

---

## Moth Phase 2 — Document and File Kit

Goal: separate document policy from text editing and UI.

Scope:

- open/save/save-as;
- line ending detection and preservation;
- encoding policy starter;
- dirty flag;
- recent files;
- recovery/autosave sidecar plan;
- file path identity;
- document title/status metadata.

Definition of done:

- Moth can open, edit, save, and recover a basic document through model APIs;
- Luna does not own document policy;
- Moth File Kit does not own rendering or widgets.

---

## Moth Phase 3 — First Luna-Hosted Editor Window

Requires: Luna Phase 3A/3B/3C text view foundation.

Goal: prove Moth can run as a thin app over Luna.

Scope:

- one Luna window;
- one Moth-backed text view;
- file open/save commands;
- basic status bar text;
- command registry connected to Luna command invocation;
- prompt-driven go-to-line;
- basic find prompt or panel starter;
- copy/paste through Luna host services.

Definition of done:

- app code uses Luna public APIs;
- editor behavior lives in Moth modules;
- platform details stay under Luna host targets;
- text view exposes accessibility semantics through Luna.

---

## Moth Phase 4 — Sublime Command Model

Requires: Luna command/quick-panel/menu primitives.

Goal: build the Sublime-like command-driven workflow.

Scope:

- `MothCommandRegistry`;
- command descriptors: ID, title, default keys, palette visibility, menu placement, arguments, enabled predicate;
- keymap model;
- command palette using Luna quick panel;
- basic fuzzy command search;
- keybinding display;
- command execution tests.

Definition of done:

- menus, shortcuts, palette, tests, and future plugins can all call the same command IDs;
- commands are typed enough to avoid stringly-typed chaos internally;
- Sublime keymap import has a clear landing model.

---

## Moth Phase 5 — Navigation

Goal: make the editor feel like Sublime rather than a basic text box.

Scope:

- Goto Anything;
- goto line;
- goto file;
- goto symbol starter;
- recent files;
- project file index starter;
- quick panel keyboard and pointer behavior through Luna.

Definition of done:

- common jump workflows are command-driven;
- quick panels are Luna UI surfaces fed by Moth data;
- file/symbol indexing stays out of Luna.

---

## Moth Phase 6 — Find / Replace

Goal: implement the core editor search workflow.

Scope:

- find panel;
- replace panel;
- find next/previous;
- highlight matches;
- case/regex/whole-word toggles;
- selection-aware search behavior;
- command/keybinding integration.

Definition of done:

- find/replace works from commands and keyboard;
- UI uses Luna bottom panel primitives;
- search logic is testable without launching the UI.

---

## Moth Phase 7 — Syntax, Theme, and Snippets

Goal: make Moth useful for real coding and start compatibility work.

Scope:

- syntax scopes;
- highlighting pipeline;
- theme mapping;
- `.sublime-color-scheme` importer starter;
- `.sublime-syntax` importer research/starter;
- snippets;
- buffer-word completion;
- keyword completion;
- snippet placeholder navigation.

Definition of done:

- plain text plus at least one real language path works;
- themes color syntax through Luna/Moth-native models;
- compatibility importers translate into native structures rather than contaminating the core.

---

## Moth Phase 8 — Workspace

Goal: move from single-file editor to Sublime-class workspace.

Scope:

- tabs;
- split panes;
- sidebar tree;
- open files section;
- project folders;
- sessions;
- recent projects;
- workspace restore;
- file indexing starter.

Definition of done:

- user can open a project, browse files, edit multiple documents, and restore a session;
- tabs/splits/sidebar are Luna widgets driven by Moth state.

---

## Moth Phase 9 — Advanced Editing

Goal: implement the muscle-memory editing features.

Scope:

- multiple cursors;
- select next occurrence;
- select all occurrences;
- column selection;
- line move/duplicate/delete;
- toggle comment;
- smart indentation;
- tab/space policy;
- auto-pair insertion;
- bracket matching;
- scroll-to-selection behavior;
- minimap integration later in the phase.

Definition of done:

- common Sublime editing actions work;
- features are command-driven;
- editing behavior is testable without launching the UI.

---

## Moth Phase 10 — Sublime Compatibility Layer

Goal: import Sublime-style assets without making Sublime formats the internal architecture.

Scope:

- `.sublime-settings` importer;
- `.sublime-keymap` importer;
- `.sublime-color-scheme` importer;
- `.sublime-syntax` importer;
- `.sublime-snippet` importer;
- `.sublime-project` importer;
- `.sublime-menu` importer.

Rule:

```text
Compatibility imports into Moth/Luna-native structures.
It does not contaminate Luna core or Moth's internal model.
```

Definition of done:

- imported assets map into typed Moth/Luna models;
- unsupported features fail loudly and are documented;
- compatibility layer is isolated and testable.

---

## Moth Phase 11 — Packages, Plugins, and Build Systems

Goal: grow into a full editor ecosystem carefully.

Scope:

- package folder layout;
- package metadata;
- command contribution points;
- menu/keymap/settings/theme/syntax/snippet loading;
- build system model;
- build output panel;
- plugin runtime research;
- Swift-first plugin model before any Python compatibility attempt.

Constraint:

- do not start here;
- packages and plugins only make sense after commands, settings, panels, syntax, and documents are stable.

Definition of done:

- static package assets load first;
- executable/plugin extension comes later and does not compromise engine boundaries.

---

## Moth Phase 12 — Beyond Sublime

Goal: keep the Sublime-class baseline while adding features Luna makes possible.

Candidate features:

- accessibility inspector;
- command graph/debugger;
- semantic project dashboard;
- built-in package manager UI;
- structured code outline panels;
- AI-assisted code tools if desired later;
- embedded/hardware developer panels;
- custom build/debug tools;
- specialized log/hex/markdown viewers;
- visual theme inspector.

Rule:

- added features should be Luna panels/widgets and Moth commands, not one-off app hacks.

---

## Long-Term Success Criteria

Moth Text succeeds when:

- it feels immediately familiar to Sublime users;
- it starts quickly;
- it handles large files without collapsing;
- multiple cursors and keyboard workflows are first-class;
- themes, settings, keymaps, snippets, syntax, and projects have compatibility paths;
- the app remains Swift-native and clean-room;
- Luna owns generic UI/runtime/platform concerns;
- editor behavior is testable outside the UI;
- accessibility is available because it was designed into the stack, not retrofitted.

---

## Current Luna Dependency

Before serious Moth implementation, Luna should finish at least:

```text
Luna Phase 2D — Layout, Resize, and Accessibility Reflow
Luna Phase 2D.2 — Universal Bounded Text and Control Reflow
Luna Phase 3A — Static Accessible Text View
Luna Phase 3B — Caret Geometry and Static Selection Model
Luna Phase 3C — Text View Scroll and Viewport
```

Moth can be designed in parallel, but the first real Moth window should wait until Luna has a resize-safe, accessibility-aware, scrollable text surface. Luna now also has locked product-neutral visual tokens, so Moth color work should map onto those token groups from Moth/app code instead of hardcoding colors into editor widgets.


---

## Luna-UI Licensing Baseline

As of Luna-UI Phase 5C.2.2, the reusable Luna-UI engine is licensed under `MPL-2.0`. As of Phase 5D, LunaUITestApp has a narrow local-file proof behind Luna workspace/document contracts. As of Phase 5D.1, the repo also includes a repeatable public-domain UTF-8 corpus for demoing and regression-testing file-backed editor behavior. As of Phase 5D.2, the Luna demo also proves new untitled buffers, safe empty local-file creation, and demo Save As routing without adding native product file dialogs yet. Moth Text remains the product/application layer built on top of Luna boundaries; product filesystem/project policy should stay outside Luna source files unless intentionally contributed to the reusable engine.
