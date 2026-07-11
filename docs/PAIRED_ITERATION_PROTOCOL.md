# Luna UI and Moth Text Paired Iteration Protocol

This document defines the required development order for changes that affect both Luna UI and Moth Text.

## Governing Order

```text
Luna change
  -> build Luna
  -> test Luna
  -> commit and push Luna
  -> update Moth's Luna submodule pointer
  -> implement Moth integration
  -> build Moth
  -> test Moth
  -> commit and push Moth
```

Moth must never consume uncommitted Luna work. Every Moth revision records a specific committed Luna revision through `Dependencies/Luna-UI`.

## Luna Iteration

Before editing:

```bash
git status --short
```

After editing:

```bash
./scripts/validate-iteration.sh
```

The Luna commit must be created and pushed before Moth updates its submodule pointer.

## Moth Consumption

From the Moth repository:

```bash
cd Dependencies/Luna-UI
git switch main
git pull --ff-only
cd ../..

git submodule status
git diff --submodule=log -- Dependencies/Luna-UI
```

Moth integration then proceeds against that exact Luna commit.

## Delivery Isolation Law

Moth ZIPs and patches must not contain or modify:

```text
Dependencies/Luna-UI/**
Dependencies/Luna-UI/.git
```

A Moth overlay contains Moth-owned files only. The submodule pointer is updated by Git in the user's real Moth checkout, never by copying Luna files into an archive.

Use:

```bash
./scripts/package-overlay.sh <output.zip>
```

The packaging script rejects tracked changes below `Dependencies/Luna-UI` and excludes the entire dependency directory from the archive.

## Validation Before Moth Commit

```bash
./scripts/validate-paired-iteration.sh

git submodule status
git diff --submodule=log
git status --short
```

The Moth commit may stage the submodule gitlink itself:

```bash
git add Dependencies/Luna-UI
```

It must not stage files from inside the Luna repository.

## Failure Conditions

Do not commit the paired Moth change when:

- Luna contains uncommitted changes;
- the checked-out Luna revision differs from Moth's recorded gitlink unexpectedly;
- Luna has not been pushed;
- Luna build or tests fail;
- Moth build or tests fail;
- a generated Moth overlay contains `Dependencies/Luna-UI`;
- implementation code crosses the Luna/Moth ownership boundary merely to avoid a proper API.
