#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "error: run this from an extracted overlay inside the Luna-UI Git repository." >&2
    exit 1
fi

# Remove any accidentally tracked recovery/worktree directories, including
# malformed nested gitlinks, then remove matching untracked copies.
mapfile -d '' tracked < <(git ls-files -z | awk -v RS='\0' 'BEGIN{ORS="\0"} {n=split($0,a,"/"); for(i=1;i<=n;i++) if(a[i] ~ /^\.fr-/){print $0; break}}')
if ((${#tracked[@]})); then
    git rm -rf --ignore-unmatch -- "${tracked[@]}"
fi

find . -depth -name '.fr-*' -print0 | while IFS= read -r -d '' path; do
    rm -rf -- "$path"
done

echo "Removed stray .fr-* repository artifacts. Review with: git status --short"
