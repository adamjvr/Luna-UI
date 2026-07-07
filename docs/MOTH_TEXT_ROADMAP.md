# Moth Text Roadmap

Moth Text is the end-user editor product. Its long-term goal is to become a Swift-native, Sublime-class text editor with clean-room Sublime compatibility and additional modern features.

Moth Text is built on Luna UI. Luna owns the reusable custom UI/runtime layer, renderer, text shaping infrastructure, accessibility tree, overlay system, platform hosts, and theme primitives. Moth owns editor product behavior: documents, buffers, commands, projects, settings policy, packages, compatibility importers, and the user-facing editor workflow.

This split is the central design decision.

---

## Product Definition

Moth Text is:

- a modern Sublime-class code/text editor;
- written in Swift;
- built on Luna UI rather than native widgets or web UI;
- macOS + Linux focused;
- command-driven;
- fast-starting and large-file capable;
- clean-room compatible with key Sublime workflows and file formats where practical;
- accessibility-first through Luna's semantic UI spine.

Moth Text is not:

- a wrapper around Sublime Text;
- a clone of Sublime internals;
- an Electron editor;
- a SwiftUI/AppKit app;
- the place where platform/rendering/accessibility infrastructure should live.

---

## Relationship to Luna UI

The intended stack is:

```text
Moth Text
  Editor product, documents, commands, projects, settings, compatibility.

Moth Editor Toolkit
  Syntax, snippets, completion providers, find/replace, settings model.

Moth Text Core
  Text buffer, selections, cursors, edit transactions, undo/redo.

Moth File Kit
  Open/save, line endings, recovery, recent files, project paths.

Moth Package Kit
  Sublime-compatible loaders, packages, plugins later.

Luna UI
  Widgets, overlays, command UI, accessibility, focus, input routing.

Luna Render / Text / Theme / Host
  Rendering, shaping, theming, host/platform abstraction.
```

Moth Text should never directly own:

- renderer backends;
- SDL/AppKit/Metal imports;
- OS accessibility bridges;
- generic prompt/list/completion UI;
- generic menu/status/overlay widgets;
- platform event loops.

Moth uses Luna services for those.

---

## Sublime Compatibility Philosophy

Moth Text should clone Sublime's user-facing behavior and workflow, not its internals.

The goal is clean-room compatibility:

```text
Sublime-style file formats and workflows
  -> translated into Moth-native typed models
  -> rendered and hosted by Luna UI
```

Compatibility loaders should be adapters, not the core architecture.

Planned importers/adapters:

- `.sublime-color-scheme` -> Luna theme tokens + syntax theme roles;
- `.sublime-syntax` -> Moth syntax definitions;
- `.sublime-keymap` -> Moth keymap entries;
- `.sublime-settings` -> Moth settings layers;
- `.sublime-snippet` -> Moth snippets;
- `.sublime-project` -> Moth project model;
- `.sublime-menu` -> Luna menu model + Moth command IDs.

Internal code should prefer typed Swift models over raw Sublime JSON/YAML structures.

---

## Feature Ownership Map

```text
Sublime-style Feature         Proper Home
------------------------------------------------------------
Command palette               Luna quick panel + Moth command registry
Goto Anything                 Luna quick panel + Moth project/file/symbol index
Find / Replace                Luna prompt/panel + Moth find engine
Completion popup              Luna popup + Moth completion providers
Menus                         Luna menu model + Moth command descriptors
Status bar                    Luna status widget + Moth status policy
Tabs and split panes          Luna layout widgets + Moth document/window model
Sidebar                       Luna tree/list widgets + Moth project model
Themes                        LunaTheme + Moth/Sublime theme importers
Syntax highlighting           MothSyntax + LunaText/LunaRender
Multiple cursors              MothTextCore
Selections                    MothTextCore
Undo / redo                   MothTextCore edit transactions
Open/save/recovery            MothFileKit
Settings hierarchy            MothSettings
Packages/plugins              MothPackageKit
Build systems                 MothBuild
Accessibility                 Luna tree + Moth editor semantics
```

---

## Phase 0 — Dependency on Luna's Architecture Spine

Status: waiting on Luna Phase 1/2 maturity.

Moth should not start by creating its own windows, prompts, popups, menus, or platform glue. The first Moth work depends on Luna proving:

- `LunaWidget` full contract;
- `LunaUIContext`;
- command dispatch path;
- prompt/list/completion modal requests;
- accessible text-view direction;
- theme tokens;
- CPU renderer correctness.

Exit criteria:

- a small non-Moth Luna demo can create a semantic widget, command action, overlay, and accessibility node without app-specific hacks.

---

## Phase 1 — Moth Core Model Bootstrap

Purpose: start Moth as editor logic, not UI machinery.

Deliverables:

- `MothTextBuffer` protocol;
- first buffer implementation, likely simple at first but replaceable;
- line index model;
- cursor model;
- multi-selection model;
- edit transaction model;
- undo/redo manager;
- command IDs for core editing actions;
- tests for basic text editing operations.

Important constraint:

The first buffer can be pragmatic, but the APIs must not assume Swift `String` indexing is the final large-file model. The long-term target is rope, piece table, or another large-document-safe structure.

Exit criteria:

- text edits are represented as transactions;
- selections and cursors are model-level concepts;
- UI code is not required to test editing behavior.

---

## Phase 2 — Document and File Kit

Purpose: separate document policy from text editing and UI.

Deliverables:

- open/save/save-as;
- line ending detection and preservation;
- file encoding policy starter;
- dirty flag;
- recent files;
- recovery/autosave sidecar plan;
- file path identity;
- document title/status metadata.

Exit criteria:

- Moth can open, edit, save, and recover a basic document through model APIs;
- Luna does not own document policy;
- Moth File Kit does not own rendering or widgets.

---

## Phase 3 — First Luna-Hosted Editor Window

Purpose: prove Moth can run as a thin app over Luna.

Deliverables:

- one Luna window;
- one Moth-backed text view;
- file open/save commands;
- basic status bar text;
- command registry connected to Luna command invocation;
- prompt-driven go-to-line;
- basic find panel/prompt;
- copy/paste through Luna host services.

Exit criteria:

- app code uses Luna public APIs;
- editor behavior lives in Moth modules;
- platform details stay under Luna host targets;
- text view exposes accessibility semantics through Luna.

---

## Phase 4 — Command Palette and Keymap System

Purpose: build the Sublime-like command-driven workflow.

Deliverables:

- `MothCommandRegistry`;
- command descriptors: ID, title, default keys, palette visibility, menu placement, arguments, enabled predicate;
- keymap model;
- command palette using Luna quick panel;
- basic fuzzy command search;
- keybinding display;
- command execution tests.

Exit criteria:

- menus, shortcuts, palette, tests, and future plugins can all call the same command IDs;
- commands are typed enough to avoid stringly-typed chaos internally;
- Sublime keymap import has a clear landing model.

---

## Phase 5 — Sublime-Compatible Theme and Syntax Starter

Purpose: make Moth feel visually familiar and start compatibility work early.

Deliverables:

- `.sublime-color-scheme` importer starter;
- syntax scope to Luna token mapping;
- initial syntax highlighter interface;
- plain text and one real language syntax path;
- theme fixtures;
- editor foreground/background/selection/caret/gutter/status tokens.

Exit criteria:

- imported color schemes can color an editor buffer;
- Moth internals use Moth/Luna-native theme models;
- compatibility parser code is isolated from rendering code.

---

## Phase 6 — Editing Features That Make It Feel Like Sublime

Purpose: move beyond a simple text box.

Deliverables:

- multiple cursors;
- add next occurrence;
- select all occurrences;
- line duplicate/delete/move;
- comment toggle;
- smart indentation;
- tab/space policy;
- auto-pair insertion;
- bracket matching;
- go to line;
- find next/previous;
- replace;
- scroll-to-selection behavior.

Exit criteria:

- common Sublime muscle-memory actions work;
- features are command-driven;
- every editing behavior is testable without launching the UI.

---

## Phase 7 — Project Model, Sidebar, and Goto Anything

Purpose: introduce the core project workflow.

Deliverables:

- project folders;
- sidebar tree using Luna widgets;
- file index;
- recent projects;
- project settings layer;
- Goto Anything quick panel;
- file fuzzy matching;
- line/column suffix parsing;
- symbol search starter.

Exit criteria:

- user can open a project, browse files, and jump quickly;
- the quick panel is shared infrastructure with command palette;
- project logic stays in Moth, while UI is Luna.

---

## Phase 8 — Tabs, Splits, and Sessions

Purpose: reach the familiar editor workspace model.

Deliverables:

- tab model;
- dirty/clean tab state;
- close/save prompts;
- split pane layout;
- active group/document model;
- session restore;
- window layout persistence.

Exit criteria:

- Moth supports multi-file editing;
- tabs and splits are Luna layout widgets driven by Moth document state;
- session restore can reopen prior workspace state.

---

## Phase 9 — Snippets and Completion

Purpose: provide useful completion before full LSP or plugin complexity.

Deliverables:

- completion provider protocol;
- buffer word provider;
- syntax keyword provider;
- snippet provider;
- Sublime snippet importer;
- completion popup through Luna;
- snippet placeholder navigation;
- manual completion command;
- auto-completion policy later.

Exit criteria:

- completion UI does not care where candidates come from;
- snippets are model-driven and testable;
- LSP can be added later as another provider rather than a redesign.

---

## Phase 10 — Packages, Plugins, and Build Systems

Purpose: grow into a full editor ecosystem carefully.

Deliverables:

- package folder layout;
- package metadata;
- command contribution points;
- menu/keymap/settings/theme/syntax/snippet loading;
- build system model;
- build output panel;
- plugin runtime research.

Constraint:

Do not start here. Packages and plugins only make sense after commands, settings, panels, syntax, and documents are stable.

Exit criteria:

- Moth can load static package assets first;
- executable/plugin extension comes later and does not compromise engine boundaries.

---

## Added Features Beyond Sublime

Moth can eventually go beyond Sublime because Luna is not Sublime-specific.

Candidate future features:

- accessibility inspector;
- command graph/debugger;
- semantic project dashboard;
- built-in package manager UI;
- structured code outline panels;
- AI-assisted refactor panels if desired later;
- embedded/hardware developer tools;
- specialized log/hex/markdown viewers;
- visual theme inspector.

These should be added as Luna panels/widgets and Moth commands, not as one-off app hacks.

---

## Long-Term Moth Text Success Criteria

Moth Text is successful when:

- it feels immediately familiar to Sublime users;
- it starts quickly;
- it handles large files without collapsing;
- multiple cursors and keyboard workflows are first-class;
- themes, settings, keymaps, snippets, syntax, and projects have compatibility paths;
- the app remains Swift-native and clean-room;
- Luna owns generic UI/runtime/platform concerns;
- editor behavior is testable outside the UI;
- accessibility is available because it was designed into the stack, not retrofitted.
