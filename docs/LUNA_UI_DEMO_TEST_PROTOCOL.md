# LunaUITestApp Demo Test Protocol

This protocol is the standing manual regression checklist for the demo app after Phase 4B.2 command routing and text-input focus cleanup.

The demo is an integration harness for Luna UI. It may show the Moth Obsidian palette as an app-supplied fixture, but Luna library APIs remain product-neutral.

---

## Feature Map

### Global commands

| Input | Expected reaction |
|---|---|
| `Ctrl+P` | Open the command palette / quick panel. |
| `Ctrl+F` | Open the generic find / replace panel. |
| `Ctrl+A` | Select all text in the editor when no overlay owns input. |
| `Escape` | Close the active modal/palette/find panel before the editor sees it. |
| Window resize | Header, editor, proof panel, overlays, and status bar reflow cleanly. |

Retired behavior:

```text
Bare 1 / 2 / 3 are no longer theme hotkeys.
They should insert text when the editor has focus.
Theme switching is command-palette-only.
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
