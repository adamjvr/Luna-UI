# Luna UI Phase 5F.1 Validation

Validated in the delivery environment:

- `LunaUI` target builds;
- `LunaUITestApp` builds;
- 192 product-neutral Luna tests pass with zero failures, including 7 new Phase 5F.1 pane/tab tests;
- 2 SDL application-contract tests pass with zero failures;
- the Linux demo maps a real 960×640 `Luna-UI CPU Demo` window and exits cleanly from `WM_DELETE_WINDOW`;
- no validation shim or build output is included in this overlay.

The delivery environment lacked the SDL2, HarfBuzz, and FreeType development
headers. Product-only and host validation therefore used temporary compile
headers against the installed runtime libraries, while the product-neutral suite
used a temporary pruned validation manifest. Run the normal commands in
`LUNA-5F1-TEST-AND-COMMIT.md` on the development workstation before committing.
