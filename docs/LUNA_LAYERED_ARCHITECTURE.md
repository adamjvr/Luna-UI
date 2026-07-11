# Luna Layered Architecture

Luna is a family of Swift libraries for custom-rendered desktop applications. Moth Text is Luna's founding application and primary design pressure, but Luna is not limited to Moth and must remain useful to unrelated applications.

This document defines the boundary between Luna's reusable mechanisms, Luna's optional document/editor-oriented components, and Moth's product behavior.

---

## Governing Principle

```text
Moth defines the pressure.
Luna defines reusable mechanisms.
Optional Luna component libraries package reusable application anatomy.
Moth owns editor meaning, workflow, compatibility, and policy.
```

Luna may know how a document workspace, text surface, search panel, completion list, gutter, tab strip, diff view, or minimap primitive is constructed. Luna must not know what Moth Text means, how Sublime compatibility is interpreted, how a project is indexed, or how source-editor commands behave.

The distinction is not "editor-related versus non-editor-related." The distinction is **reusable capability versus product policy**.

---

## Relationship to Sublime's UI Strategy

Luna follows the same broad architectural direction demonstrated publicly by Sublime Text and Sublime Merge:

- the application owns a custom widget and rendering stack;
- most interior application UI is drawn consistently by that stack across platforms;
- native platform layers provide windows, input, IME, accessibility bridges, dialogs, clipboard, drag and drop, cursors, display information, and other system services;
- the shared UI stack is broad enough to support more than one product.

Luna does not attempt to copy Sublime's proprietary internals. It adopts the proven separation between a shared custom UI platform and product-specific application behavior.

---

## The Four Product Levels

### Level 1 — Luna Foundation

Required by nearly every Luna application:

```text
LunaCore
LunaAccessibility
LunaCommands
LunaInput
LunaLayout
LunaRender
LunaTheme
LunaHostCore
platform host/render backends
```

Responsibilities include stable identities, geometry, scheduling/invalidation contracts, display lists, rendering, input normalization, focus primitives, command descriptions, accessibility semantics, themes, and platform seams.

### Level 2 — Luna General UI

General-purpose application components:

```text
LunaUI / future LunaWidgets
LunaMenus
LunaOverlays
LunaCollections
```

Responsibilities include buttons, labels, fields, menus, lists, trees, tables, tabs, split containers, scroll areas, overlays, dialogs, status surfaces, and reusable interaction behavior.

The current repository still places many of these in the `LunaUI` target. Splitting the physical targets is an incremental roadmap task, not a prerequisite for preserving the logical boundary today.

### Level 3 — Luna Document and Developer UI

Optional reusable libraries for document-heavy and editor-adjacent applications:

```text
LunaText
LunaTextEditing
LunaDocumentUI
LunaEditorComponents
LunaDiffUI
LunaConsoleUI
```

Potential responsibilities include:

- generic editable text models suitable for controls and lightweight documents;
- text layout, caret and selection geometry;
- generic document/view identity protocols;
- search and replace panel UI;
- line-number and annotation gutters;
- document tab strips and workspace shells;
- completion and suggestion surfaces;
- text decorations;
- diff, log, console, and minimap primitives;
- generic undo/transaction interfaces and sensible default implementations.

These libraries are optional. A normal Luna application should not be forced to depend on the complete editor-oriented stack.

### Level 4 — Moth Text

The product layer:

```text
MothTextCore
MothEditor
MothSyntax
MothWorkspace
MothCompatibility
MothPackages
MothApplication
```

Moth owns:

- production source buffers and large-file policy;
- source-editor selections and multiple cursors;
- edit transaction and undo grouping semantics;
- Sublime command behavior, settings, keymaps, themes, projects, snippets, syntax, packages, and compatibility adapters;
- project indexing and Goto Anything ranking;
- transient/semi-transient sheet policy;
- document lifecycle and session policy;
- language servers, syntax engines, completion providers, and diagnostics;
- Moth-specific filesystem, recovery, save, and close behavior;
- the Moth visual identity and built-in product themes.

---

## Mechanism, Default, and Policy

Luna may provide mechanisms and optional defaults. Moth owns product policy.

| Capability | Luna mechanism/default | Moth policy |
|---|---|---|
| Search | Search panel, query controls, result presentation, optional plain-string provider | Buffer search semantics, scopes, history, wrap policy, editor selection integration, undo grouping |
| Tabs | Layout, overflow, pin visuals, drag/reorder, keyboard traversal, accessibility | Transient sheets, dirty-file meaning, preview behavior, cloned views, close/save policy |
| Splits | Generic split containers, pane identity, resize handles, focus traversal | Editor groups, active view routing, cloned buffer placement, session persistence |
| Completion | Anchored suggestion popup, list navigation, details, activation payload | Candidate providers, ranking, snippets, LSP, insertion and commit-character behavior |
| Undo | Generic transaction interfaces and command integration | Typing coalescence, multi-cursor edits, source transformations |
| Gutter | Generic rows, markers, hit targets, annotations | Diagnostics, bookmarks, breakpoints, Git state, code folding |
| Minimap | Miniature viewport and projection/render hooks | Source-text projection, syntax colors, viewport policy, editor commands |
| Documents | Generic IDs, descriptors, view identity, lightweight default models | Files, projects, recovery, encoding policy, source buffers, sessions |

---

## Current-Code Classification

No current feature should be deleted merely because it is editor-adjacent. Existing proof code should be classified and separated at logical seams.

### Keep in Luna foundation/general UI

- display lists and renderer contracts;
- host input and dialog contracts;
- semantic widgets and accessibility nodes;
- layout, menus, overlays, quick panels, context menus, generic tabs, status surfaces, split layouts;
- theme tokens and resolved visual styles;
- generic scroll and viewport behavior.

### Keep as optional Luna document/editor components

- lightweight editable text model;
- caret and selection geometry;
- generic text view and gutter rendering;
- generic search-panel UI;
- optional literal/regex search utility detached from panel state;
- completion popup;
- document/workspace descriptors and projection helpers;
- generic editor/workbench shell renamed or scoped to avoid product assumptions.

### Move to or recreate in Moth

- production source-buffer implementation;
- Moth edit transaction and undo model;
- multi-cursor selection set;
- source-oriented find session and replacement policy;
- Moth document/workspace/session policy;
- project indexing, syntax, snippets, language services, packages, and Sublime compatibility.

---

## Dependency Laws

```text
Moth may depend on optional Luna document/editor components.
Optional Luna components may depend on Luna foundation and general UI.
Luna foundation/general UI must not depend on Moth.
Normal Luna applications must not be forced to import editor-oriented modules.
Platform and renderer backend details must not leak into widgets or product code.
```

During the current repository phase, these laws may be represented by folders, protocols, and tests before every logical layer becomes a separate SwiftPM target.

---

## Promotion Test for Luna APIs

A capability may live in Luna when all of the following are true:

1. It can be named without Moth or Sublime product terminology.
2. Its state and behavior can be supplied by an application rather than reading Moth globals.
3. At least one plausible non-Moth application can use it.
4. Its platform details remain below host/render boundaries.
5. Applications that do not need it can avoid its heavier dependencies, either now or through the planned module split.

A second working consumer is preferred before declaring an API stable. `LunaUITestApp` may serve as a proof consumer, but a future non-Moth reference application should validate generality before Luna 1.0.

---

## Immediate Architectural Objective

Before adding more editor-shell behavior, establish the layered boundary in code without performing a rewrite:

- inventory `Sources/LunaUI` by foundation, general UI, optional document/editor component, and Moth-policy risk;
- introduce protocols or data-provider seams where UI and algorithms are fused;
- detach find/search presentation from buffer-search policy;
- distinguish lightweight generic editable text from the future Moth production buffer;
- establish buffer-versus-view identity so two views can share one document while keeping independent selection and scroll state;
- document target dependency rules and add architecture tests preventing upward dependencies;
- retain all current demo behavior and performance baselines.

Only after this boundary pass should tab overflow, pinned-tab refinement, and split/pane work proceed. Those features will then land in the correct reusable component layer rather than hardening accidental monolithic APIs.

## Phase 5E.2 adapter boundary

The optional document/editor component layer now exposes value snapshots rather
than retaining application buffers:

```text
Application-owned source buffer
    -> LunaTextStorageAdapter
        -> LunaTextStorageSnapshot
            -> reusable Luna text views and panels
```

A `LunaDocumentViewPresentationState` belongs to one presentation, not to the
shared document. Caret, selection, preferred column, scroll state, and observed
revision therefore remain independent when multiple views consume the same
snapshot identity.

Find presentation follows the same rule. `LunaFindResultsProviding` supplies
results, and `LunaFindPanelSession` receives semantic actions. Luna does not own
source-editor scanning indexes, replacement transactions, or undo grouping.
