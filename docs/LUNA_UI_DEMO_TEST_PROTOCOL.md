# LunaUITestApp Demo Test Protocol

This protocol is the standing manual regression checklist for the demo app through Convergence C2.3. It retains the earlier file/dialog/proof-gallery checks and adds current pane, selection, exact geometry, scrolling, and rapid-input latency checks.

The demo is an integration harness for Luna UI. It may show the Moth Obsidian palette as an app-supplied fixture, but Luna library APIs remain product-neutral.

---

## Feature Map

### Global commands

| Input | Expected reaction |
|---|---|
| `Ctrl+P` | Open the command palette / quick panel. |
| `Ctrl+F` | Open the generic find / replace panel. |
| `Ctrl+A` | Select all text in the editor when no overlay owns input. |
| `Ctrl+Space` | Open the anchored completion popup near the text caret. |
| `Escape` | Close the active modal/palette/find panel/menu/context menu/completion popup before the editor sees it. |
| Window resize | Menu bar, tab strip, sidebar, editor content, overlays, and status bar reflow cleanly; proof panel reflows in proof-gallery mode. |

Retired behavior:

```text
Bare 1 / 2 / 3 are no longer theme hotkeys.
They should insert text when the editor has focus.
Theme switching is command-palette-only.
```

---

## Convergence C1A/C1B Editor Interaction Protocol

Run the explicit editor performance harness with a disposable long-line file or the built-in document:

```bash
swift run LunaUITestApp --editor
```

| Action | Expected reaction |
|---|---|
| Hover editable text | Native cursor becomes an I-beam. |
| Hover near the split center rule | The forgiving semantic divider target highlights and shows the horizontal resize cursor. |
| Drag the divider away from its original bounds | Pointer capture keeps the divider gesture active until release; both panes rewrap. |
| Click text | Caret moves to the UTF-8-safe hit location. |
| Shift-click elsewhere | Selection extends from the existing application-owned anchor. |
| Click-drag across lines and wrapped continuation rows | Selection tracks smoothly and remains clipped to the pane. |
| Double-click a word containing non-ASCII text | The complete Unicode-aware word run is selected on valid UTF-8 boundaries. |
| Double-click whitespace or punctuation | Only the contiguous whitespace or punctuation run is selected. |
| Triple-click a logical line | The full line is selected, including its newline when another line follows. |
| Drag above or below the text viewport | Time-throttled visual-row autoscroll advances while selection continues. |
| Alt-Tab or otherwise lose pointer capture during a drag | The text/divider gesture cancels cleanly and does not remain stuck. |
| Begin a text drag near the divider | Exactly one gesture owns pointer motion; text selection and divider resizing do not compete. |

Boundary rule:

```text
Luna owns reusable gesture interpretation, cursor/capture mechanics, text coordinates, and autoscroll requests.
The demo owns editable document state, selection storage, viewport state, and command/file policy.
```

---

## License / Project Metadata Protocol

Phase 5C.2.2 is a project-infrastructure checkpoint. It should not change demo behavior, but the repository metadata should stay consistent.

Core checks:

| Check | Expected reaction |
|---|---|
| Inspect `LICENSE` | The file contains Mozilla Public License Version 2.0 text. |
| Search for old license references | No project source or documentation should refer to the old license. |
| Inspect Swift/package files | Files begin with concise `SPDX-License-Identifier: MPL-2.0` headers, with `Package.swift` keeping `// swift-tools-version` first. |
| Run `--editor` harness | Behavior remains responsive and event-driven with current file/dialog lifecycle support. |
| Run proof-gallery mode | Proof surfaces remain available; moving-square animation advances smoothly from logical animation time and animation-only static-frame reuse. |

---



### Phase 5D.3.1 — Proof Gallery Animation Pacing

At the Phase 5D.3.1 checkpoint, the then-default editor harness remained event-driven while proof-gallery animation became explicitly time-based and stall-tolerant. C2.3 keeps that behavior in explicit `--editor` mode and restores the cached kitchen-sink presentation as the default. The moving proof square advances from a host-runtime `LunaAnimationClock` with clamped logical deltas instead of deriving position directly from absolute uptime or frame count.

Core checks:

| Action | Expected reaction |
|---|---|
| Run `swift run LunaUITestApp` | C2.3 kitchen-sink mode is visible and includes the proof animation. |
| Run `swift run LunaUITestApp --proof-gallery` | Proof panel, moving square, semantic widget proof, and HUD are visible. |
| Watch the moving square | Motion is smooth and bounded inside the proof panel. |
| Trigger a dialog or briefly stall the app, then return | The moving square resumes without jumping across the proof panel. |
| Inspect status bar in proof-gallery mode | Animation diagnostics show frame delta/phase and animation invalidation appears during continuous proof rendering. |
| Inspect explicit `--editor` status bar | No animation status segment appears in lean editor mode. |



### Phase 5D.3.2 — Proof Gallery Static Frame Cache

Phase 5D.3.2 keeps the Phase 5D.3.1 logical animation clock, then removes the remaining proof-gallery sluggishness by caching the static proof-gallery frame. Animation-only frames restore that cached frame and redraw only the moving square and small HUD diagnostics. The full editor shell, sidebar, status labels, and text viewport are rebuilt only when input, document state, theme, overlay state, workspace state, or window size invalidates them.

Core checks:

| Action | Expected reaction |
|---|---|
| Run `swift run LunaUITestApp --proof-gallery` | Proof-gallery mode opens with the proof panel and moving square. |
| Watch the moving square without touching the UI | Motion stays smooth; the editor text/sidebar should not feel like it is being recomputed every frame. |
| Open a menu/context/completion/find overlay | The demo falls back to full redraw while overlays are active, preserving correct z-order. |
| Close the overlay and keep watching | Animation returns to the lightweight animation-only path. |
| Resize or switch theme | The static proof-gallery cache is refreshed before animation-only frames resume. |
| Run `swift run LunaUITestApp --editor` | The explicit editor harness remains event/invalidation driven and does not use proof-gallery continuous animation. |

Boundary rule:

```text
The static frame cache is demo/proof-gallery policy.
It is not a LunaUI retained-mode rewrite.
```

Boundary rule:

```text
Proof-gallery animation is demo/stress-harness behavior.
The explicit `--editor` harness stays event/invalidation driven.
LunaUI widgets do not become async or frame-count-driven animation objects.
```

---

## Real File I/O Protocol

Phase 5D adds a narrow local-file proof in the demo app. The filesystem adapter lives in `LunaUITestApp`; LunaUI continues to own only product-neutral file/document descriptors, open/save request/result contracts, and routing helpers.

Run the explicit editor harness with a real repository file:

```bash
swift run LunaUITestApp --editor --open README.md
```

Equivalent launch forms:

```bash
swift run LunaUITestApp README.md
LUNA_DEMO_OPEN_FILE=README.md swift run LunaUITestApp
```

Core checks:

| Action | Expected reaction |
|---|---|
| Launch with `--open README.md` | README opens as a real local UTF-8 document and becomes the active tab. |
| Inspect sidebar | A `Local Files` root appears with the opened file row; existing demo fixture project rows still work. |
| Type into the local file | The tab/document becomes dirty. |
| `File > Save` | The local file is written through the app-owned adapter and the dirty marker clears. |
| Modify local file and an in-memory fixture, then `File > Save All` | Both dirty document types route through the same save request/result seam; local disk errors are reported as status. |
| Close clean local tab | Targeted close routing removes the local tab and syncs workspace/shell state. |
| Close dirty local tab | Host dialog boundary prompts Save / Don’t Save / Cancel; Cancel preserves the dirty tab. |
| Launch with a missing path | Demo reports a file-not-found status instead of crashing. |
| Launch proof gallery with a file | `swift run LunaUITestApp --proof-gallery --open README.md` keeps proof surfaces available while opening the real file through the same adapter. |

Boundary rule:

```text
The demo app owns local filesystem access, path display, extension-to-syntax hints, and disk errors.
LunaUI owns only product-neutral descriptors, request/result shapes, routing, and projection helpers.
```

---


## Public-Domain Demo Corpus Protocol

Phase 5D.1 adds a checked-in UTF-8 text corpus under `Examples/PublicDomainDemoFiles`. The corpus exists to make real-file demos repeatable without editing important user files.

Verify the corpus manifest:

```bash
./scripts/verify-public-domain-demo-files.py
```

Open the largest fixture:

```bash
swift run LunaUITestApp --open-demo-corpus=largest
# equivalent helper path:
./scripts/run-demo-corpus.sh --largest
```

Open multiple fixtures:

```bash
swift run LunaUITestApp --open-demo-corpus=frankenstein
swift run LunaUITestApp --open-demo-corpus=caesar
swift run LunaUITestApp --open-demo-corpus=all
```

Core checks:

| Action | Expected reaction |
|---|---|
| Run `./scripts/verify-public-domain-demo-files.py` | The manifest reports all checked-in demo corpus files as present with matching byte counts and SHA-256 hashes. |
| Launch `--open-demo-corpus=largest` | The largest Frankenstein excerpt opens as a real file-backed local document. |
| Launch `--open-demo-corpus=frankenstein` | Six Frankenstein excerpt tabs become available under the `Local Files` sidebar root. |
| Launch `--open-demo-corpus=caesar` | Six Latin excerpt tabs become available under the `Local Files` sidebar root. |
| Launch `--open-demo-corpus=all` | All twelve `.txt` fixtures are registered/opened without breaking tab/document identity. |
| Run `./scripts/run-demo-corpus.sh --proof-gallery --largest` | Proof-gallery mode still works while opening a corpus file through the same local adapter seam. |
| Edit a disposable copy of a fixture and save | Save routes through the Phase 5D app-owned adapter and clears dirty state. |

Boundary rule:

```text
The corpus is a demo/test fixture, not a LunaUI source-code dependency.
The helper flags merely expand to local file paths before the existing Phase 5D adapter opens them.
```

## Phase 5D.2 — New File / Untitled Buffer / Save As Proof

Phase 5D.2 completed the basic file lifecycle proof without adding product-specific Moth policy. Phase 5D.3 now routes visible Open / Save As / dirty-close behavior through an app/host dialog boundary. Untitled documents are app-owned demo buffers with no file destination until Save As; created empty files and Save As targets are local-file adapter operations owned by `LunaUITestApp`.

```bash
swift run LunaUITestApp --new-untitled
mkdir -p /tmp/luna-ui-new-file-proof
swift run LunaUITestApp --create /tmp/luna-ui-new-file-proof/new-note.txt
swift run LunaUITestApp --new-untitled --save-as /tmp/luna-ui-new-file-proof/untitled-saved-as.txt
# Then choose File > Save As… in the app.
```

| Action | Expected result |
|---|---|
| File > New File or Ctrl+N | Opens `Untitled-N.txt` as an empty, clean, closable tab with no sidebar file selected. |
| Type into an untitled document | The tab/status dirty state changes exactly like a file-backed document. |
| Save an untitled dirty document | The editor requests a Save As destination through the host dialog boundary. With `--save-as`, the scripted dialog supplies the destination repeatably. |
| Save As… | Writes the active document to the selected local path, registers it under `Local Files`, and converts an untitled tab to a file-backed document. |
| Launch with `--create path` | Creates a new empty UTF-8 local file, refuses to overwrite by default, registers it under `Local Files`, and opens it as a real file-backed buffer. |
| Launch with `--overwrite-create --create path` | Explicitly allows replacing the target file for testing only. |


## Phase 5D.3 — Host Dialog Boundary for Native Open / Save / Dirty Close

Phase 5D.3 keeps OS dialogs out of LunaUI while making the editor demo behave like a normal desktop editor. LunaHostCore now exposes neutral dialog request/result types and an injectable `LunaDialogService`. `LunaUITestApp` uses that service for File > Open…, Save-on-untitled, File > Save As…, and dirty close Save / Don’t Save / Cancel decisions.

```bash
# Script the File > Open… dialog for deterministic testing.
swift run LunaUITestApp --dialog-open README.md

# Script Save As… for an untitled document.
mkdir -p /tmp/luna-ui-dialog-proof
swift run LunaUITestApp --new-untitled --save-as /tmp/luna-ui-dialog-proof/saved-from-dialog.txt

# Script dirty close choice while keeping the same command path.
LUNA_DEMO_DIALOG_UNSAVED_DECISION=discard swift run LunaUITestApp --new-untitled
```

| Action | Expected result |
|---|---|
| File > Open… | Interactive runs use the host desktop dialog provider when available; scripted runs use `--dialog-open` / `LUNA_DEMO_DIALOG_OPEN_PATH`. The selected file opens through the existing Phase 5D adapter. |
| File > Save on a file-backed dirty document | Saves silently to the existing file path through the local-file adapter. |
| File > Save on an untitled dirty document | Requests a Save As destination through `LunaDialogService`; scripted `--save-as` paths remain available for regression testing. |
| File > Save As… | Always requests a destination through the dialog service. |
| Close a dirty tab/document | Requests Save / Don’t Save / Cancel through the dialog service. Save writes before close, Don’t Save closes without saving, Cancel leaves the document open. |
| Headless or missing desktop helper | The command reports an unavailable/cancelled dialog status and preserves user data. CLI/scripted paths still work. |

Boundary rule:

```text
LunaUI owns document state, dirty state, command routing, and neutral request/result seams.
The editor demo/host owns native dialog providers and filesystem path policy.
Future Luna-rendered file-management widgets can satisfy LunaDialogService later without replacing the host boundary.
```

---

## Targeted Tab / Document Close Protocol

Phase 5C.2.1 wires tab close affordances into document/workspace close policy. Closing a tab should target the clicked or right-clicked tab, not blindly close whatever document is active.

Core checks:

| Action | Expected reaction |
|---|---|
| Click the close affordance on a clean active tab | The document closes, the tab disappears, workspace open-file state updates, and a sensible neighboring document becomes active. |
| Click the close affordance on a clean inactive tab | The clicked inactive document closes while the current active document remains active. |
| Right-click a tab and choose `Close Tab` | The right-clicked tab/document is the close target. |
| Keyboard-activate `Close Tab` from a tab context menu | The context menu still uses the tab that opened the menu as the close target. |
| `File > Close Document` | Closes the active document because the command has no explicit target. |
| Close dirty document/tab | Host dialog boundary asks Save / Don’t Save / Cancel; cancel preserves the tab and document contents. |
| Close non-closable tab | Command is disabled or reports non-closable target. |

Boundary rule:

```text
The tab strip detects close intent; document/workspace command policy decides what actually closes.
Commands stay generic and receive target document identity through LunaCommandContext metadata.
```

---

## Editor Harness / Proof Gallery Protocol

C2.3 restores the complete kitchen-sink presentation as the default while retaining a separate lean editor harness for responsiveness measurements.

Run default kitchen-sink demo:

```bash
swift run LunaUITestApp
```

Run the lean editor performance harness:

```bash
swift run LunaUITestApp --editor
# or
LUNA_DEMO_MODE=editor swift run LunaUITestApp
```

Run the legacy proof-gallery compatibility spelling:

```bash
swift run LunaUITestApp --proof-gallery
# or
LUNA_DEMO_MODE=proof swift run LunaUITestApp
```

Core checks:

| Action | Expected reaction |
|---|---|
| Launch default app | Opens the complete kitchen-sink mode with editor shell, proof panel, HUD, and moving square. |
| Default app at rest | The proof panel and HUD are visible; the square continues moving while static editor surfaces remain cached between animation-only frames. |
| Default app status bar | Shows mode, frame timing, invalidation, and input coalescing diagnostics. |
| Move pointer rapidly across stable empty/editor areas | Pointer-motion storms are coalesced; redraws occur only for meaningful state changes. |
| Drag-select text | Drag still works; coalescing preserves the latest drag endpoint per frame. |
| Click tabs/sidebar/menu/context/completion | Non-motion semantic events are preserved and routed normally. |
| Run `--editor` | Proof-only surfaces are hidden and the app becomes the lean event-driven performance harness. |
| Run `--proof-gallery` | Compatibility mode retains the proof panel, moving block, semantic widget, and HUD. |
| Set `LUNA_DEMO_DEBUG_COMMANDS=1` | Command-request stdout logging is enabled. |
| Default logging | Command-request stdout spam is suppressed. |

Boundary rule:

```text
The default demo is the complete kitchen-sink regression presentation.
`--editor` is the lean input/render performance harness.
Proof-gallery remains a compatibility regression/stress spelling.
Luna remains state-driven; this is not a retained-mode rewrite.
Hosts invalidate on state change, not on mere pointer hits.
```

---

## Runtime / Frame Pacing Protocol

Phase 5C.1 adds the host-runtime frame pacing and invalidation boundary. The demo should no longer behave like an unconditional game loop that redraws forever while idle. Host code records frame timing, tracks why a frame was requested, and avoids double-throttling when SDL vsync already owns presentation pacing.

Core checks:

| Action | Expected reaction |
|---|---|
| Start the demo and stop touching input | CPU usage should settle significantly lower than the old unconditional redraw loop. |
| Move/click/type/resize | The host records an invalidation reason and renders a new frame. |
| Type into the editor | Invalidation reasons include text/document activity and dirty document state still updates. |
| Open menus/palette/context/completion/find | Overlay input still works and requests frames through the UI lane. |
| Status bar | Shows frame timing, recent invalidation reasons, mode, and input coalescing diagnostics. |
| Linux/SDL presenter | Uses vsync as the timing authority and does not also unconditionally `SDL_Delay(16)` after every present. |

Boundary rule:

```text
Luna widgets remain synchronous and deterministic.
Host runtimes own frame pacing and invalidation scheduling.
Applications/services may do async work, but async results must return to the UI lane as snapshots/events before mutating Luna state.
```

---

## Command Runtime Protocol

Phase 5B adds the product-neutral command runtime that future Moth surfaces should use instead of ad-hoc demo-specific dispatch. The demo still owns the handlers, but menus, context menus, the command palette, and keyboard shortcuts now resolve through one runtime-backed command path.

Core checks:

| Action | Expected reaction |
|---|---|
| `Ctrl+P` | Opens command palette through the command keymap. |
| `Ctrl+F` | Opens find/replace through the command keymap. |
| `Ctrl+A` | Runs the same Select All command used by menus/context/palette. |
| `Ctrl+Space` | Opens completion popup through the command keymap. |
| `Edit > Select All` | Runs the same command ID as `Ctrl+A`. |
| `Selection > Select All` | Runs the same command ID as `Ctrl+A`. |
| `Editor context > Select All` | Runs the same command ID as `Ctrl+A`. |
| Command palette > `Select All` | Runs the same command ID as `Ctrl+A`. |
| `Theme` menu/context submenu | Active theme check mark follows command availability state. |
| `View > Toggle Sidebar` / sidebar context/status context | Sidebar checked/visible state comes from command availability and the same handler. |

Boundary rule:

```text
LunaCommands owns descriptor/availability/keymap/runtime plumbing.
LunaUITestApp owns demo handlers.
Moth will later provide its own handlers and policy.
```

---

## Workspace / Project Adapter Protocol

Phase 5C adds the product-neutral file/project adapter boundary. The demo still uses an in-memory adapter, but the sidebar tree, open-file behavior, Save, Save All, and dirty close policy now flow through Luna workspace descriptors and request/result contracts instead of hardcoded demo-only sidebar commands.

Core checks:

| Action | Expected reaction |
|---|---|
| Open the app at rest | Sidebar tree is projected from a `LunaProjectTreeSnapshot`, not hand-built static sidebar rows. |
| Click `Sources > LunaUI > LunaDocumentBuffer.swift` | The file opens through `LunaWorkspaceAdapter` and becomes the active editor document. |
| Click `Sources > LunaUI > LunaEditorShell.swift` | A different adapter-backed document opens/activates. |
| Click `docs > LUNA_UI_ROADMAP.md` / roadmap row | Markdown fixture opens through the same file-open command shape. |
| Type into an opened file | Active document becomes dirty while other documents remain unchanged. |
| `File > Save` | Active dirty document is saved through `LunaDocumentSaveRequest` / `LunaDocumentSaveResult`; dirty indicator clears. |
| Modify multiple documents then `File > Save All` | All dirty demo documents are saved through the adapter boundary. |
| `File > Close Document` on clean closable doc | Document closes through dirty-close policy. |
| `File > Close Document` on dirty doc | Demo reports the save-prompt decision instead of silently closing. |
| Status bar | Includes project/workspace metadata plus active document metadata. |

Boundary rule:

```text
Luna owns file/project IDs, descriptors, tree snapshots, adapter contracts, and projection helpers.
The demo adapter owns fake file contents.
The demo now also owns a small local-filesystem adapter behind this seam; Moth will later replace it with real product filesystem/project policy.
```

---

## Document / Buffer Protocol

Phase 5A is the first real multi-document proof. As of Phase 5D.3, the demo still keeps the original in-memory fixture documents but can also open real local UTF-8 files, create empty local files, and create untitled buffers; all paths route through product-neutral `LunaDocumentStore` buffers.

Open documents to test:

```text
Overview.swift
EditorSurface.swift
Theme.json
```

| Action | Expected reaction |
|---|---|
| Click `Overview.swift` tab | The active tab changes and the editor text changes to the overview buffer. |
| Click `EditorSurface.swift` tab | The active tab changes and the editor text changes back to the editor-surface buffer. |
| Click `Theme.json` tab | The active tab changes and the editor text changes to JSON fixture text. |
| Type in the active tab | Only that document buffer changes. The active tab gains a dirty/modified indicator. |
| Switch away and back | The typed text, caret/selection, and logical scroll state for that document are preserved. |
| Click open-document rows in the sidebar | The corresponding document becomes active, matching tab and editor text. |
| Status bar after tab switch | Document title, syntax, revision, dirty/saved state, scroll, and caret position reflect the active document. |

Boundary rule:

```text
Phase 5A itself did not do file I/O or Moth project policy. Phase 5D adds demo-owned local file I/O behind the same document/workspace seam, Phase 5D.2 adds untitled/new-file lifecycle coverage, and Phase 5D.3 adds host-dialog routing while preserving product-neutral document identity, open-buffer state, tab projection, dirty tracking, and active-buffer routing.
```

---

## Completion Popup Protocol

The Phase 4F completion popup is a product-neutral Luna anchored-popup proof. The demo supplies static editor-like suggestions; LunaUI supplies item/state shape, anchor-relative layout, row geometry, hit testing, pointer/keyboard routing, theme-driven display-list geometry, and accessibility.

Open with:

```text
Ctrl+Space
```

| Action | Expected reaction |
|---|---|
| `Ctrl+Space` with editor focused | Completion popup opens near the visible caret. |
| Move caret near lower/right viewport edge, then open | Popup clamps inside the window and flips above the anchor when needed. |
| `Up` / `Down` | Moves selected suggestion. |
| `PageUp` / `PageDown` | Jumps selection by the visible row count. |
| `Home` / `End` | Moves to first/last enabled suggestion. |
| Hover a suggestion row | Highlight follows the hovered row. |
| Click an enabled suggestion | Inserts its demo insertion text or routes its command, then closes. |
| `Enter` / `Tab` | Accepts the selected suggestion. |
| `Escape` | Dismisses the popup. |
| Click outside the popup | Dismisses without moving the editor caret underneath. |

Completion demo checks:

| Suggestion | Expected reaction |
|---|---|
| `let`, `var`, `struct` | Inserts keyword text at caret or replaces selection. |
| `LunaTheme`, `LunaMenuItem`, `LunaCompletionPopup` | Inserts the selected type name. |
| `Show Completion Info` | Routes through `LunaCommandID` and opens a modal notice instead of inserting text. |

Input ownership rule:

```text
The completion popup owns navigation, Enter, Tab, Escape, hover, and click activation.
Unhandled normal text input still belongs to the editor/application policy path.
```

---

## Context Menu Protocol

The Phase 4E context menu is a product-neutral Luna floating-menu proof. The demo chooses different context definitions for editor text/content, tabs, sidebar rows, and status-bar segments; LunaUI supplies positioned layout, row geometry, hit testing, pointer/keyboard routing, and accessibility.

Open with:

```text
secondary-click / right-click
```

Surfaces to test:

```text
editor text/content area
tabs and tab close areas
sidebar file/folder rows
status-bar segments
```

| Action | Expected reaction |
|---|---|
| Right-click editor text/content | Opens an editor context menu with Copy/Cut/Paste Sample, Select All, Clear Selection, Find, Theme, and Info rows. |
| Right-click a tab | Opens a tab context menu with Activate, Close, checked Pinned state where applicable, Reveal, Theme, and Info rows. |
| Right-click a sidebar row | Opens a sidebar context menu with Open/Reveal/Rename, disabled New File, Toggle Sidebar, Theme, and Info rows. |
| Right-click a status segment | Opens a status context menu with Toggle Sidebar, scroll commands, Theme, and Info rows. |
| Hover a context row | Row highlight changes using menu theme tokens. |
| Click enabled row | Command runs and context menu closes. |
| Click disabled row | Context menu consumes the click, does not run a command, and remains open. |
| Click outside an open context menu | Context menu closes; underlying editor/shell does not accidentally activate. |
| `Escape` with context menu open | Context menu closes. |
| `Up` / `Down` with context menu open | Moves highlighted row, skipping separators and disabled rows. |
| `Right` on a submenu row | Opens the submenu. |
| `Left` inside a submenu | Returns to parent row; at root it dismisses the context menu. |
| `Enter` / `Space` | Activates the highlighted command or opens the highlighted submenu. |

Context command checks:

| Context path | Expected reaction |
|---|---|
| `Editor > Paste Sample Text` | Inserts `context-menu` at the caret or replaces selection. |
| `Editor > Select All` | Selects the entire editor document. |
| `Editor > Find / Replace…` | Opens the find panel. |
| `Theme` submenu | Shows the active theme check mark and can switch themes. |
| `Context Menu Info` | Opens a modal notice explaining the context-menu primitive. |
| Disabled rows such as `Cut`, `New File`, or `Close Other Tabs` | Remain visible but inactive. |

Input ownership rule:

```text
When a context menu is open, keyboard/pointer/text input belongs to it until it closes.
No context-menu navigation key or click should leak into the editor or shell underneath.
```

---

## Editor Shell Protocol

The Phase 4D editor shell is product-neutral Luna infrastructure. The demo supplies fake tabs, a fake project tree, and dynamic status segments; LunaUI supplies layout, state shape, hit testing, theme-driven geometry, and accessibility.

Visible shell pieces to test:

```text
tab strip above the editor
left project/sidebar tree
editor content frame
bottom status bar segments
```

| Action | Expected reaction |
|---|---|
| App at rest | Tabs, sidebar rows, editor text surface, proof panel when wide, and status segments are all visible. |
| Resize window wide/narrow | Sidebar/content/proof panel reflow without text or hit-test bounds drifting. |
| Click a tab | Active tab changes and status reports the tab command. |
| Click a closable tab's close box | Close-tab command is requested; demo keeps static fixture tabs. |
| Click sidebar disclosure arrows | Folder rows expand/collapse. |
| Click a sidebar file row | Row selection changes and routes a demo command. |
| Click inside the editor content frame | Text caret/selection still works; shell does not consume editor-content clicks. |
| Click status segments | Clickable segments route commands where provided; non-command status text remains inert. |
| Switch themes | Tab/sidebar/status backgrounds and labels update from theme tokens. |

Input ownership rule:

```text
The shell owns tab/sidebar/status hits only.
Editor content hits continue to flow to the text view.
Menus, palette, find panel, and modals still sit above the shell and own input while open.
```

---

## Menu Bar Protocol

The top menu bar is a Phase 4C product-neutral Luna menu proof. The demo supplies editor-like menu contents; LunaUI supplies menu layout, input, rendering geometry, hit testing, and accessibility.

Top-level menus to test:

```text
File
Edit
Selection
Find
View
Theme
Help
```

| Action | Expected reaction |
|---|---|
| Top menu bar at rest | `File`, `Edit`, `Selection`, `Find`, `View`, `Theme`, and `Help` labels are visible against the menu-bar background. |
| Click a top-level menu | Opens its dropdown with visible row titles, shortcut labels, check marks, and submenu arrows. |
| Move pointer across top-level menus while a menu is open | Active dropdown switches to the hovered top-level menu. |
| Hover a command row | Row highlight changes using menu theme tokens. |
| Click enabled command row | Command runs and menu closes. |
| Click disabled row | Menu consumes the click, does not run a command, remains sane. |
| Click outside an open menu | Menu closes; underlying editor does not accidentally edit/click. |
| `Escape` with menu open | Menu closes. |
| `Up` / `Down` with menu open | Moves highlighted row. |
| `Left` / `Right` with menu open | Moves top-level menu or opens/closes submenu level. |
| `Enter` / `Space` with menu open | Activates highlighted command or opens highlighted submenu. |

Menu command checks:

| Menu path | Expected reaction |
|---|---|
| `Edit > Select All` | Selects entire editor document. |
| `Edit > Insert Sample Text` | Inserts `quick-panel` at caret or replaces selection. |
| `Selection > Clear Selection` | Clears active user text selection. |
| `Find > Find / Replace…` | Opens find panel. |
| `View > Command Palette…` | Opens command palette. |
| `View > Scroll Text View to Top` | Scrolls editor to top. |
| `View > Scroll Text View to End` | Scrolls editor to bottom. |
| `Theme > Luna Demo Blue` | Switches to blue proof theme. |
| `Theme > Moth Obsidian Demo` | Switches to black/graphite Moth demo theme. |
| `Theme > High Contrast Proof` | Switches to high-contrast proof theme. |
| `Help > Show Demo Notice` | Opens modal notice. |

Theme menu check mark:

```text
Open Theme menu after switching themes.
Expected: active theme row has the checked mark.
```

Input ownership rule:

```text
When a menu is open, keyboard/pointer events belong to the menu until it closes.
No menu navigation key should leak into the editor underneath.
```

---

## Command Palette Protocol

Open with:

```text
Ctrl+P
```

| Action | Expected reaction |
|---|---|
| Type query | Palette query changes; editor text does not change. |
| `Backspace` | Edits palette query. |
| `Up` / `Down` | Moves selected command. |
| `PageUp` / `PageDown` | Jumps selected command. |
| `Home` / `End` | Moves to first/last result. |
| `Enter` | Runs selected command and closes the palette. |
| `Escape` | Closes the palette without running a command. |
| Mouse click row | Runs clicked command. |

Queries to test:

```text
theme
moth
blue
contrast
select all
find
notice
scroll
sample
sidebar
tab
```

Expected command reactions:

| Command | Expected reaction |
|---|---|
| `Theme: Luna Demo Blue` | Switches to blue proof theme. |
| `Theme: Moth Obsidian Demo` | Switches to black/graphite Moth demo theme. |
| `Theme: High Contrast Proof` | Switches to high-contrast proof theme. |
| `Select All` | Selects the entire editor document. |
| `Open Find / Replace Panel` | Opens the find panel. |
| `Show Demo Notice` | Opens modal notice. |
| `Scroll Text View to Top` | Scrolls editor to top. |
| `Scroll Text View to End` | Scrolls editor to bottom. |
| `Insert Sample Text` | Inserts `quick-panel` at the caret or replaces selection. |
| `Toggle Sidebar` | Shows/hides the Phase 4D sidebar shell region. |
| `Activate Editor Tab` / related tab commands | Updates active tab state and status text. |

Input ownership rule:

```text
While the palette is open, its keyboard/text input never leaks into the editor.
```

---

## Theme Protocol

Theme switching is now via command palette only:

```text
Ctrl+P -> type "moth" / "blue" / "contrast" -> Enter
```

Moth Obsidian expected colors:

| Role | Color |
|---|---|
| Window/background black | `#070709` |
| Graphite button/control | `#131416` |
| Dark gray layer | `#242426` |
| Light gray text | `#888991` |
| Text highlight/accent | `#003CFF` |

High Contrast expected highlight behavior:

| Role | Color |
|---|---|
| Moving proof block | `#FFCC00` |
| User text selection | `#FFCC00` |
| Current find match | `#FFCC00` |
| Text-field selection token | `#FFCC00` |

Moth mode visual test:

```text
Ctrl+P -> moth -> Enter
select text
open Ctrl+F
open Ctrl+P
scroll and type
```

Expected:

```text
background stays black/obsidian
controls remain graphite/dark gray
text remains light gray
actual text selection/focus/highlight uses blue
bright Luna demo blue does not leak into Moth mode
```

---

## Text Editor Protocol

### Basic editing

| Action | Expected reaction |
|---|---|
| Click text | Caret moves to clicked line/column. |
| Type letters | Inserts letters at caret. |
| Type `123` | Inserts `123`; does not switch themes. |
| `Enter` | Inserts newline. |
| `Backspace` | Deletes before caret, or deletes current selection. |
| `Delete` | Deletes after caret, or deletes current selection. |
| `Left` / `Right` | Moves caret; collapses selection if one exists. |

Test sequence:

```text
Click inside editor.
Type: abc123
Press Enter.
Type: second line
Use Left/Right.
Backspace/Delete text.
```

Expected:

```text
text mutates
caret follows edits
status bar updates line/column/revision
bare numbers remain editable text
```

### Select all

| Action | Expected reaction |
|---|---|
| `Ctrl+A` | Selects the complete editor document. |
| `Ctrl+P -> select all -> Enter` | Same as `Ctrl+A`. |
| Type after Select All | Replaces the whole document. |
| Backspace/Delete after Select All | Deletes the whole document. |

Test sequence:

```text
Ctrl+A
Type: replacement
```

Expected:

```text
all previous text is replaced by replacement
selection clears
caret lands after replacement
revision increments
no stray "a" from Ctrl+A appears before replacement
```

Shortcut text suppression check:

```text
Ctrl+A
Type: replacement
```

Bad result:

```text
areplacement
or the old document plus replacement appended somewhere
```

Good result:

```text
replacement
```

---

## Interactive Text Selection Protocol

| Action | Expected reaction |
|---|---|
| Click-drag one line | Selected range highlights with accent color. |
| Click-drag across lines | Multiline selection rectangles appear. |
| Click elsewhere | Selection clears and caret moves. |
| Shift-click | Extends selection from anchor/caret to clicked location. |
| Shift+Left / Shift+Right | Extends selection by one text position. |
| Plain Left / Right with selection | Collapses selection toward start/end. |
| Type while selected | Replaces selected range. |
| Backspace/Delete while selected | Deletes selected range. |

Highlight separation rule:

```text
current-line highlight != user text selection != find-result highlight
```

---

## Scrolling Protocol

| Input | Expected reaction |
|---|---|
| `Up` / `Down` | Scrolls one logical line. |
| `PageUp` / `PageDown` | Scrolls by a page-ish chunk. |
| `Home` | Jumps to top. |
| `End` | Jumps to bottom. |

Test sequence:

```text
End
click visible text
type a few characters
Home
PageDown
click visible text again
```

Expected:

```text
visible line range updates
scrollbar thumb/lane updates
hit testing accounts for scrollTopLine
caret status reports real document location
```

---

## Find / Replace Protocol

Open with:

```text
Ctrl+F
```

| Action | Expected reaction |
|---|---|
| Type query | Query field updates; editor text does not change. |
| `Enter` | Find next. |
| `Shift+Enter` | Find previous. |
| `Tab` | Switch between find and replace fields. |
| `Backspace` | Edits focused field. |
| `Escape` | Closes find panel. |
| Click toggles | Case/whole-word/regex options refresh matches. |
| Click Replace | Replaces current match. |
| Click All | Replaces all matches. |

Queries to test:

```text
phase
theme
line
Luna
```

Input ownership rule:

```text
While the find panel is open, its keyboard/text input never leaks into the editor.
```

---

## Modal Protocol

From the command palette, run `Show Demo Notice`.

Expected:

```text
modal appears above editor/palette layer
modal captures pointer/keyboard first
Enter activates default button
Escape cancels/closes
resize keeps modal readable
button hover/press states work
```

---

## Full Regression Checklist

```text
1. Build and run LunaUITestApp.
2. Ctrl+P -> moth -> Enter; confirm black/graphite theme.
3. Click editor and type abc123; confirm numbers insert.
4. Ctrl+A; confirm all text selects.
5. Type replacement; confirm full-document replacement.
6. Select text by dragging.
7. Replace selected text by typing.
8. Delete selected text with Backspace/Delete.
9. Scroll with PageDown/End.
10. Click text after scrolling.
11. Ctrl+F, search for a word.
12. Replace one match.
13. Ctrl+P, run Theme: Luna Demo Blue.
14. Ctrl+P, run Theme: Moth Obsidian Demo.
15. Ctrl+P, run Theme: High Contrast Proof; confirm selection/highlight yellow matches the moving block.
16. Ctrl+P, run Show Demo Notice.
17. Escape closes active overlay first.
18. Resize window wide/narrow.
19. Confirm header/editor/proof panel/status remain readable.
```


## Convergence C2.2 geometry and scrolling regression

Run the focused automated suites before the graphical pass:

```bash
swift test --filter LunaTextRenderTests
swift test --filter LunaUIPhase5F2ATests
swift test --filter LunaHostSDLApplicationTests
```

Then launch the default kitchen-sink demo:

```bash
swift run LunaUITestApp
```

Verify:

- type or paste a long line quickly; the caret stays at the exact rendered end and does not drift by accumulating rounded cell widths;
- click insertion boundaries along the line; hit testing and the caret agree with the painted glyph run;
- selection rectangles begin and end at the same shaped insertion positions;
- soft wrapping uses shaped row width and remains stable after window resize;
- the mouse wheel scrolls the text surface vertically;
- precise touchpad deltas accumulate smoothly instead of being promoted to three-row wheel notches;
- clicking above or below the scrollbar thumb pages the viewport;
- dragging the scrollbar thumb captures the pointer, clamps at both ends, and releases on mouse-up or capture loss;
- C2.2 does not add horizontal editor scrolling, bidi layout, font fallback chains, or product document tabs.


## Convergence C2.4 interactive-runtime regression

The default document contains more than 340 deterministic rows. Verify full-range
wheel movement, touchpad accumulation, scrollbar paging, thumb dragging, blank
rows, long soft-wrap paragraphs, tabs, precomposed/decomposed accents, Greek, and
Cyrillic text.

In `--editor` mode, hold a printable key for at least ten seconds and type rapidly
on a long row. Then immediately trigger Ctrl+S, arrow navigation, menu activation,
and pointer clicks. Repeat with a pointer-motion storm before a click and a long
scroll gesture before menu activation. Every barrier action must react promptly;
there must be no series of unrelated full-frame presentations before it.

The diagnostics should report acquisition and semantic batch data plus
input-to-present latency. A raw polling limit may cause another acquisition pass,
but must never itself cause a frame. Arrow keys, Backspace, Delete, commands,
pointer events, resize, focus, and capture loss remain ordering barriers and must
never be merged into text.
