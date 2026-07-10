# LunaUITestApp Demo Test Protocol

This protocol is the standing manual regression checklist for the demo app after Phase 5B product-neutral command runtime.

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
| Window resize | Header, menu bar, tab strip, sidebar, editor content, proof panel, overlays, and status bar reflow cleanly. |

Retired behavior:

```text
Bare 1 / 2 / 3 are no longer theme hotkeys.
They should insert text when the editor has focus.
Theme switching is command-palette-only.
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

## Document / Buffer Protocol

Phase 5A is the first real multi-document proof. The demo still uses in-memory fixture documents, not file I/O, but tabs and open-document state now route through product-neutral `LunaDocumentStore` buffers.

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
Phase 5A does not do file I/O or Moth project policy.
It proves product-neutral document identity, open-buffer state, tab projection, dirty tracking, and active-buffer routing.
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
