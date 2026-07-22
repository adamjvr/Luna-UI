# Text Geometry and Scrolling Contract

Convergence C2.2 makes one immutable shaped row the authority for production text
geometry. Document coordinates remain UTF-8 offsets. Horizontal positions remain
HarfBuzz 26.6 values until Luna produces final integer framebuffer rectangles.

## Geometry flow

```text
source UTF-8 row
    -> product geometry provider
    -> shaped glyph clusters and grapheme insertion positions
    -> LunaStaticTextRowGeometry
         +-> soft-wrap boundaries
         +-> caret rectangle
         +-> selection/highlight rectangles
         +-> pointer hit testing
         +-> production row painting
```

`LunaStaticTextGeometryRequest` supplies both the complete logical line and the
UTF-8 range being presented. This preserves line-relative context such as tab
stops when a soft-wrapped continuation begins in the middle of a line.
`LunaStaticTextRowGeometry` may carry a different `renderedText` when presentation
expands source characters such as tabs, but every insertion position remains in
source UTF-8 coordinates. Request ranges and arbitrary offsets inside a grapheme
resolve to the preceding stable insertion boundary.

The production Unicode path must not derive caret X from `characterCount *
roundedAdvance`. Fixed-cell geometry remains available only as a deterministic
fallback for diagnostic renderers and callers that do not inject a shaper.

## Paint order

Editor products should paint in this order:

```text
background and current-line state
highlights and selection
text glyphs
scrollbar thumb
caret
focus border and transient overlays
```

Painting the caret after glyphs prevents a glyph mask from obscuring the insertion
indicator.

## Scroll input

`LunaScrollEvent` is platform-neutral and contains location, two-axis deltas,
phase, precision, and modifiers. Positive vertical delta means movement toward
later document rows. Host adapters own native sign conventions.

`LunaStaticTextScrollInteraction` converts events into viewport requests:

- conventional wheel notches move three visual rows;
- precise deltas retain a fractional remainder supplied and stored by the product;
- the pane beneath the pointer receives wheel input without necessarily becoming
  the active editing pane;
- lane clicks page by one viewport minus one row;
- thumb dragging uses pointer capture and clamps to the legal visual-row range.

Luna does not own document or viewport persistence. Products apply returned row
requests to their own view state.

## Deferred work

C2.2 does not implement horizontal editor scrolling, the Unicode bidirectional
algorithm, script segmentation, variable-font fallback chains, or multiple open
documents. Those require later explicit phases rather than hidden extensions of
this contract.


## C2.3 latency follow-up

C2.3 did not change the C2.2 shaped coordinate model. Its retained contributions
are committed-text authority, timing diagnostics, and the restored demo corpus.
Its raw-batch presentation policy failed native acceptance and is superseded by
C2.4. No text-geometry consumer may infer presentation timing from native polling
limits.


## C2.4 runtime correction

C2.4 does not change C2.2 shaped coordinates or scroll ownership. It changes when
semantic input reaches those systems and when their visible state is presented.
Raw native acquisition boundaries are no longer frame boundaries. Exact text and
caret geometry, wheel/trackpad routing, pane-local viewport state, and scrollbar
interaction remain unchanged and stay in the permanent regression gate.
