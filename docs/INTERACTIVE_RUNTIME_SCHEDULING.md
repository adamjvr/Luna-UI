# Interactive Runtime and Presentation Scheduling

## Ownership

`LunaHostSDL` owns native acquisition and presentation. `LunaHostCore` owns the
platform-neutral scheduler and policy values. LunaUI widgets remain synchronous
and deterministic, and downstream applications continue to own product meaning.

## Persistent semantic scheduler

`LunaInteractiveInputScheduler` survives native polling passes. It keeps a compact
FIFO with a read cursor, pending latest pointer motion, and pending committed text.
It preserves event order while allowing only compatible contiguous state to
coalesce.

Ordering barriers include pointer down/up, keyboard events, scrolling, resize,
focus/capture loss, and quit. Pending motion or text is flushed before a barrier.
Consecutive resize events may collapse only when no other semantic event separates
them. Capture loss and quit are immediate control events. Pointer activation,
fresh key presses, and modified key commands request prompt dispatch; unmodified
key-repeat, scroll, and resize streams remain ordered but may batch within the
strict latency and semantic-work limits.

## Presentation policy

`LunaInteractivePresentationPolicy` controls maximum semantic-input age,
coalesced-text byte count, and queued semantic-event count. It does not limit raw
acquisition. A batch becomes ready when:

- a prompt interaction or immediate control event has been acquired;
- the native queue is idle;
- accumulated committed text reaches its byte threshold;
- queued semantic work reaches its bounded threshold; or
- the oldest pending event reaches the monotonic latency deadline.

The SDL runner may perform multiple bounded acquisition passes without rendering.
It processes one ready semantic batch, unions scene invalidations, and presents
only when a frame is actually requested. Pending scheduler work prevents idle or
software-pacing sleeps. External VSync remains the sole display pacing authority
when available.

## Invariants

- Raw polling limits never define frame boundaries.
- No event is dropped or reordered across a barrier.
- Text never merges across commands, navigation, pointer actions, or focus changes.
- A click cannot remain behind obsolete pointer motion.
- Native acquisition can continue without forcing intermediate full-frame draws.
- Input-to-present timing uses the oldest dispatched semantic event timestamp.

## Regression coverage

The focused suite covers acquisition boundaries, 500-motion click storms,
committed text across many acquisition passes followed by a command, sustained
text deadline dispatch, idle flushing, resize collapse, repeat backlogs followed
by fresh navigation, semantic-work threshold dispatch, and immediate capture-loss
barriers. Full native graphical acceptance remains required because perceived
latency includes real SDL queueing, CPU drawing, texture upload, compositor, and
input-device behavior.
