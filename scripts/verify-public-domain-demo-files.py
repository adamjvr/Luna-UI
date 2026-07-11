#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Verify Luna UI public-domain demo corpus manifest entries.

This script intentionally uses only the Python standard library so it can run on
normal developer machines before launching LunaUITestApp with the checked-in
Phase 5D.1 text corpus.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
from typing import Any


def load_manifest(root: Path) -> dict[str, Any]:
    manifest_path = root / "manifest.json"
    try:
        return json.loads(manifest_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"error: missing manifest: {manifest_path}")
    except json.JSONDecodeError as error:
        raise SystemExit(f"error: invalid JSON in {manifest_path}: {error}")


def sha256_hex(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify(root: Path, verbose: bool) -> int:
    manifest = load_manifest(root)
    entries = manifest.get("files")
    if not isinstance(entries, list):
        print("error: manifest.json must contain a 'files' array", file=sys.stderr)
        return 2

    failures: list[str] = []
    manifest_paths: set[Path] = set()

    for raw_entry in entries:
        if not isinstance(raw_entry, dict):
            failures.append("manifest contains a non-object file entry")
            continue
        rel_path = raw_entry.get("path")
        expected_bytes = raw_entry.get("bytes")
        expected_sha256 = raw_entry.get("sha256")
        if not isinstance(rel_path, str) or not isinstance(expected_bytes, int) or not isinstance(expected_sha256, str):
            failures.append(f"invalid manifest entry: {raw_entry!r}")
            continue

        relative = Path(rel_path)
        if relative.is_absolute() or ".." in relative.parts:
            failures.append(f"unsafe manifest path: {rel_path}")
            continue

        path = root / relative
        manifest_paths.add(relative)
        if not path.is_file():
            failures.append(f"missing file listed in manifest: {rel_path}")
            continue

        data_size = path.stat().st_size
        actual_sha256 = sha256_hex(path)
        if data_size != expected_bytes:
            failures.append(f"byte mismatch for {rel_path}: manifest={expected_bytes}, actual={data_size}")
        if actual_sha256 != expected_sha256:
            failures.append(f"sha256 mismatch for {rel_path}: manifest={expected_sha256}, actual={actual_sha256}")
        if verbose:
            print(f"ok {rel_path} {data_size} bytes {actual_sha256}")

    discovered_text_files = {path.relative_to(root) for path in root.rglob("*.txt")}
    unlisted_text_files = sorted(discovered_text_files - manifest_paths)
    for rel_path in unlisted_text_files:
        failures.append(f"text fixture is not listed in manifest: {rel_path.as_posix()}")

    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1

    print(f"Verified {len(entries)} manifest entries in {root}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify Luna UI public-domain demo corpus checksums.")
    parser.add_argument(
        "corpus_root",
        nargs="?",
        default="Examples/PublicDomainDemoFiles",
        help="Path to the corpus root containing manifest.json. Defaults to Examples/PublicDomainDemoFiles.",
    )
    parser.add_argument("--verbose", action="store_true", help="Print one line per verified file.")
    args = parser.parse_args()
    return verify(Path(args.corpus_root).resolve(), args.verbose)


if __name__ == "__main__":
    raise SystemExit(main())
