# Luna UI Public-Domain Demo Files

This directory contains editable UTF-8 plain-text fixtures for demonstrating and regression-testing Luna UI's Phase 5D real-file I/O path without risking important user files.

The files are intentionally small enough to inspect manually, but varied enough to exercise tabs, sidebar paths, save behavior, search, selection, line wrapping pressure, and multi-file launch flows.

## Contents

- `frankenstein/`: six excerpts from Mary Shelley's *Frankenstein; or, The Modern Prometheus*.
- `caesar_de_bello_gallico/`: six Latin excerpts from Julius Caesar's *Commentarii de Bello Gallico*.
- `manifest.json`: filenames, byte sizes, and SHA-256 checksums for the corpus files.

## Quick launch

From the repository root:

```bash
swift run LunaUITestApp --open-demo-corpus=largest
swift run LunaUITestApp --open-demo-corpus=frankenstein
swift run LunaUITestApp --open-demo-corpus=caesar
swift run LunaUITestApp --open-demo-corpus=all
```

You can also use the helper script:

```bash
./scripts/run-demo-corpus.sh --largest
./scripts/run-demo-corpus.sh --frankenstein
./scripts/run-demo-corpus.sh --caesar
./scripts/run-demo-corpus.sh --all
./scripts/run-demo-corpus.sh --proof-gallery --largest
```

The helper verifies this manifest before launching the demo.

## Suggested manual tests

1. Open the largest fixture and confirm it appears under the `Local Files` sidebar root.
2. Type into the file and confirm the active tab becomes dirty.
3. Use `File > Save` on a disposable copy and confirm the dirty marker clears.
4. Open several fixtures at once and close tabs using both the tab close button and the tab context menu.
5. Use find/replace, selection, keyboard navigation, and completion popup commands with a file-backed document active.
6. Re-run `./scripts/verify-public-domain-demo-files.py` to confirm the checked-in fixtures still match `manifest.json`.

For destructive save tests, copy a fixture to `/tmp` first:

```bash
cp Examples/PublicDomainDemoFiles/frankenstein/06_final_pursuit_chapter_24.txt /tmp/luna-save-test.txt
swift run LunaUITestApp --open /tmp/luna-save-test.txt
```

## Public-domain and source notes

The underlying works are in the public domain in the United States. These excerpts were prepared from Project Gutenberg plain-text editions:

- Mary Shelley, *Frankenstein; or, The Modern Prometheus*, Project Gutenberg eBook #84.
- Julius Caesar, *C. Iuli Caesaris De Bello Gallico, I-IV*, Project Gutenberg eBook #218.

The Project Gutenberg license boilerplate was not copied into every fixture. The files include simple descriptive headers added specifically for this Luna UI demo corpus. Project Gutenberg's name is used only for source attribution.

Users outside the United States should verify local copyright law before redistribution.
