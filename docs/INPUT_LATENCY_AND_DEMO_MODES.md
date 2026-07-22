# Input Latency and Demo Modes

Convergence C2.3 addresses a host-loop failure mode exposed by rapid Moth typing:
an unbounded SDL queue drain could continue processing repeated keyboard and text
events before the next framebuffer was presented. Document state remained correct,
but visible text and caret updates could trail sustained input.

## Frame-fair polling

`LunaInputPollingBudget` provides two independent limits. The default interactive
budget permits at most 96 raw SDL events or approximately 2 ms of polling in one
host loop. Reaching either limit is a conservative backlog signal. The host renders
and presents the current state, skips an additional pacing sleep, and resumes the
queue on the next loop. Quit, resize, capture-loss, command, pointer, and navigation
events preserve their original order.

## Committed text

Printable text is authoritative only through `SDL_TEXTINPUT`. Plain printable
key-down events are therefore not forwarded as semantic keyboard events. Modified
shortcut keys and non-text keys remain visible. Once translated, adjacent committed
text events may concatenate into one `LunaTextInputEvent`; any other event flushes
the pending text first. This allows applications to perform one buffer transaction,
history update, caret update, and visibility calculation for a rapid text batch.

## Diagnostics

`LunaInputPollingStats`, `LunaInputCoalescingStats`, and
`LunaFrameTimingSample.inputToPresentNanoseconds` report polling cost, conservative
backlog state, merged text events, and presentation latency. Diagnostics are
observational and do not change widget or document policy.

## Demo modes

The default `swift run LunaUITestApp` launch is the complete kitchen-sink demo. It
contains the editor shell, interactive text panes, proof panel, HUD, animated
bouncing square, and a deterministic 340-row scrolling corpus.

`swift run LunaUITestApp --editor` selects the lean event-driven performance
harness. `--proof-gallery` remains a compatibility spelling for focused legacy
proof checks.
