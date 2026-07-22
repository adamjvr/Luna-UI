# Input Latency and Demo Modes

## C2.3 result and rejection

C2.3 correctly restored the complete kitchen-sink demo, added a deterministic
340-row scroll corpus, retained an explicit `--editor` performance mode, made
`SDL_TEXTINPUT` authoritative for printable text, and added useful timing and
coalescing diagnostics.

Its host scheduling policy failed graphical acceptance. It stopped raw SDL polling
after a count/time budget and treated that acquisition boundary as a reason to
render and present. Under a backlog, clicks and commands could remain deeper in the
native queue while several full CPU framebuffer presentations occurred first.
Raw acquisition boundaries therefore became accidental semantic and frame
boundaries. That behavior is rejected and must not return.

## C2.4 scheduling contract

C2.4 separates three authorities:

```text
native input acquisition
        -> persistent semantic scheduling
        -> visible-state presentation
```

`LunaInputPollingBudget` is now only a safety limit for one native acquisition
pass. Reaching it means “continue acquisition”; it never means “present now.”
`LunaInteractiveInputScheduler` retains compatible coalescing state across passes.
Pointer motion keeps the latest sample, adjacent committed text merges, and every
click, key command, navigation event, resize, focus/capture loss, and quit request
is an ordering barrier. Pointer activation, fresh key presses, modified commands,
and control loss request prompt dispatch. Unmodified repeat, scroll, and resize
streams remain ordered but may batch within the policy deadline.

A semantic batch is emitted for prompt/control input, when the native source
becomes idle, when accumulated text reaches its byte threshold, when queued
semantic work reaches its bounded threshold, or when the oldest pending event
reaches its monotonic presentation deadline. Rendering occurs only when scene
invalidation says visible state changed.

## Demo modes

```bash
swift run LunaUITestApp
```

The default remains the full kitchen-sink demo with editor surfaces, long scroll
corpus, proof panel, diagnostics HUD, and animated square.

```bash
swift run LunaUITestApp --editor
```

The editor mode remains the event-driven latency and rendering baseline.

```bash
swift run LunaUITestApp --proof-gallery
```

The compatibility spelling remains available for focused proof-gallery testing.

## Acceptance

Native acceptance must exercise motion storms followed by clicks, rapid text
followed immediately by commands, key repeat followed by navigation, scroll input
followed by menu activation, pointer capture loss, resize storms, and idle input.
No command may be delayed merely because a raw polling limit was reached. VSync
owns display synchronization; Luna must not add an independent post-present delay
while semantic work remains pending.
