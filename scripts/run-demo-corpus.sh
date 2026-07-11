#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/run-demo-corpus.sh [selection] [demo flags]

Selections:
  --largest       Open the largest Frankenstein fixture only.
  --frankenstein  Open all Frankenstein fixtures.
  --caesar        Open all Caesar / De Bello Gallico fixtures.
  --all           Open every .txt fixture in the corpus. Default.

Demo flags passed through:
  --proof-gallery Run LunaUITestApp in proof-gallery mode.
  --editor        Run LunaUITestApp in editor mode.

Examples:
  ./scripts/run-demo-corpus.sh --largest
  ./scripts/run-demo-corpus.sh --frankenstein
  ./scripts/run-demo-corpus.sh --proof-gallery --largest
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
corpus_root="${LUNA_DEMO_CORPUS_ROOT:-$repo_root/Examples/PublicDomainDemoFiles}"
selection="all"
demo_args=()

for arg in "$@"; do
  case "$arg" in
    --largest)
      selection="largest"
      ;;
    --frankenstein)
      selection="frankenstein"
      ;;
    --caesar|--de-bello-gallico)
      selection="caesar"
      ;;
    --all)
      selection="all"
      ;;
    --proof-gallery|--proof|--editor|--debug-commands)
      demo_args+=("$arg")
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

python3 "$repo_root/scripts/verify-public-domain-demo-files.py" "$corpus_root"

case "$selection" in
  largest)
    files=("$corpus_root/frankenstein/06_final_pursuit_chapter_24.txt")
    ;;
  frankenstein)
    mapfile -t files < <(find "$corpus_root/frankenstein" -type f -name '*.txt' | sort)
    ;;
  caesar)
    mapfile -t files < <(find "$corpus_root/caesar_de_bello_gallico" -type f -name '*.txt' | sort)
    ;;
  all)
    mapfile -t files < <(find "$corpus_root" -type f -name '*.txt' | sort)
    ;;
  *)
    echo "error: internal selection failure: $selection" >&2
    exit 2
    ;;
esac

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "error: no demo corpus files selected from $corpus_root" >&2
  exit 1
fi

cd "$repo_root"
exec swift run LunaUITestApp "${demo_args[@]}" "${files[@]}"
