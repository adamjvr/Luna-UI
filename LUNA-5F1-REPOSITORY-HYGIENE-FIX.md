# Luna UI 5F.1 repository hygiene correction

This correction removes accidental `.fr-*` recovery/worktree artifacts from the
Git index and working tree and prevents them from being added again. It does not
change Luna UI runtime behavior or public APIs.
