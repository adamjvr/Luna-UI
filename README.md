# Luna UI

**Luna UI** is a from-scratch, cross-platform UI and rendering engine written in Swift. It exists as the foundational UI layer for **Moth Text** — a modern, Sublime-class text editor — but it is intentionally designed as a **standalone, reusable UI framework** that can power other applications in the future.

This repository is **not an app**.

It is the engine.

Luna UI is where rendering, layout, text shaping, input, theming, and platform abstraction live. Moth Text is simply the first (and primary) consumer of this engine.

---

## Why Luna UI Exists

Moth Text is not built on top of SwiftUI, AppKit, GTK, Qt, Electron, or any web stack. That decision is deliberate.

Existing UI frameworks fail hard on the things that matter most for a serious text editor:

- Precise pixel control
- Deterministic layout and rendering
- Large-document performance
- Proper complex text shaping (ligatures, bidi, combining marks)
- Theme compatibility with editors like Sublime Text
- Cross-platform visual parity

Rather than fight those frameworks, Luna UI replaces them entirely.

Luna UI gives Moth Text:

- A **fully custom rendering pipeline**
- **Pixel-identical UI** across macOS and Linux
- A **text-first architecture**, not a widget-first one
- Long-term freedom to target Metal, Vulkan, or pure CPU rendering without rewriting the app

This is the same philosophical move that Sublime Text made years ago — but implemented in Swift, with modern GPU expectations, and without legacy baggage.

---

## Relationship to Moth Text

Think of the stack like this:

```
Moth Text (application)
└── Luna UI (engine)
    ├── Rendering & compositing
    ├── Text layout & shaping
    ├── Event & input system
    ├── Theme & styling system
    ├── Platform abstraction (macOS / Linux)
    └── GPU / CPU backends
```

- **Moth Text** defines *what* the editor does
- **Luna UI** defines *how* it is drawn, interacted with, and rendered

Moth Text has no dependency on native UI widgets. Windows, panels, tabs, text views, gutters, cursors, selections — all of it is implemented using Luna UI primitives.

This repository exists so Luna UI can evolve independently, be tested in isolation, and potentially be reused in other projects.

---

## Design Goals

Luna UI is opinionated. Every major decision in this codebase exists to satisfy one or more of the following goals.

### 1. Pixel-Exact Rendering

If a rectangle is supposed to be 1px wide at `(x: 12, y: 7)`, that is where it is drawn. No layout drift. No fractional rounding surprises. No OS-specific padding heuristics.

This matters enormously for:

- Text cursor placement
- Selection rendering
- Grid alignment
- Font metrics
- Theme accuracy

### 2. Text Is a First-Class Citizen

Luna UI is built around text, not widgets.

That means:

- Proper Unicode shaping from day one
- Ligatures, combining marks, emoji, and bidi text are non-negotiable
- Line layout and glyph positioning are explicit and inspectable
- Rendering large documents is a core requirement, not an afterthought

### 3. Cross-Platform Visual Parity

Moth Text must look the same on macOS and Linux.

Not “close enough.”

The same theme, the same spacing, the same glyph metrics, the same animations.

### 4. GPU-Accelerated, CPU-Capable

Luna UI supports:

- GPU rendering (Metal, Vulkan)
- CPU fallback rendering for bring-up, testing, and debugging

The CPU renderer is not a toy. It is a correctness reference.

### 5. Long-Term Maintainability

This is not a prototype.

The codebase favors explicit data flow, clear ownership, minimal magic, and boring, readable abstractions.

---

## Philosophy & Principles

Luna UI exists because everything else breaks down at the exact point where serious editors start to matter.

This project follows the same mindset I bring to hardware, firmware, and systems engineering work: eliminate unknowns, own the stack, and never hide complexity behind abstractions you can’t reason about.

Core principles:

- **Precision over convenience** — every pixel and glyph must land exactly where intended
- **Control over abstraction** — if we can’t inspect it, debug it, or reason about it, it doesn’t belong here
- **Performance over guesswork** — large documents are normal, not an edge case
- **Cross-platform by design** — parity is engineered, not hoped for

Luna UI is intentionally narrow so it can be brutally good at what it does.

---

## Non-Goals

Luna UI is intentionally *not* trying to be everything.

It does **not** aim to:

- Replace SwiftUI for general app development
- Compete with Qt, GTK, or Electron as a universal UI toolkit
- Provide drag-and-drop designers or visual editors
- Abstract rendering details away to the point of opacity
- Optimize for rapid prototyping over correctness
- Chase native platform look-and-feel conventions

If something reduces determinism, predictability, or performance, it does not belong here.

---

## Architecture Overview

```
+---------------------------------------------------+
|                   Moth Text                       |
|        (Editor logic, buffers, commands)          |
+-----------------------+---------------------------+
                        |
                        v
+---------------------------------------------------+
|                    Luna UI                        |
|                                                   |
|  +---------------------------------------------+  |
|  | Layout & UI Primitives                      |  |
|  |  - Explicit geometry                        |  |
|  |  - Panels, views, regions                   |  |
|  +---------------------------------------------+  |
|                                                   |
|  +---------------------------------------------+  |
|  | Text System                                 |  |
|  |  - Unicode shaping                          |  |
|  |  - Glyph layout & metrics                   |  |
|  |  - Cursor & selection                      |  |
|  +---------------------------------------------+  |
|                                                   |
|  +---------------------------------------------+  |
|  | Event & Input System                        |  |
|  |  - Keyboard, mouse, scroll                  |  |
|  |  - Deterministic dispatch                   |  |
|  +---------------------------------------------+  |
|                                                   |
|  +---------------------------------------------+  |
|  | Rendering & Compositing                     |  |
|  |  - Draw lists                               |  |
|  |  - Damage & redraw                          |  |
|  +---------------------------------------------+  |
|                                                   |
|  +----------------------+----------------------+  |
|  | CPU Renderer         | GPU Renderers        |  |
|  | (Reference / Debug)  | (Metal / Vulkan)     |  |
|  +----------------------+----------------------+  |
+---------------------------+-----------------------+
                            |
                            v
+---------------------------------------------------+
|           Platform Abstraction Layer               |
|   (macOS / Linux windowing, timing, input)        |
+---------------------------------------------------+
```

Rule of thumb:

> Platform code never leaks upward, and rendering details never leak sideways.

---

## Why Swift

Swift is a deliberate, pragmatic choice.

It provides predictable performance, strong typing, value semantics, and memory safety without a garbage collector. It also allows direct, first-class access to Metal while remaining far more maintainable than C++ and less restrictive than Rust for UI-heavy work.

### Why Not C++

C++ carries decades of legacy complexity and footguns that actively work against maintainability in large UI systems.

### Why Not Rust

Rust enforces correctness through friction that slows iteration in UI and rendering code, where experimentation and tuning are constant.

### Why Not SwiftUI

SwiftUI optimizes for developer convenience.

Luna UI optimizes for deterministic rendering, explicit layout control, and cross-platform parity.

Swift the language is the tool.

SwiftUI the framework is the wrong abstraction.

---

## Comparison: Luna UI vs SwiftUI / Qt / Electron

| Criteria                     | Luna UI              | SwiftUI           | Qt / GTK          | Electron         |
|-----------------------------|----------------------|-------------------|-------------------|------------------|
| Pixel-exact control         | Yes                  | No                | Varies            | No               |
| Text shaping correctness    | First-class          | Limited           | Varies            | Browser-driven   |
| Cross-platform parity       | Explicit             | Apple-first       | Toolkit-specific  | Browser quirks   |
| Large-doc performance       | Engine-focused       | Not optimized     | Variable          | Poor             |
| Rendering backend control   | CPU / GPU pluggable  | Locked            | Locked            | None             |

This isn’t about being “better.” It’s about solving a very specific problem without compromise.

---

## What This Enables in Moth Text

Luna UI unlocks capabilities that are not realistically achievable on top of existing UI frameworks:

- Pixel-perfect cursor and selection rendering
- Consistent glyph shaping across platforms
- Efficient redraw for very large files
- Explicit layout pipelines with no hidden heuristics
- Clean separation between editor logic and rendering

In short: Luna UI makes a serious text editor *possible*.

---

## Current State

Luna UI is under active development.

- macOS is the primary development platform
- Linux is a first-class target
- CPU rendering exists as a correctness reference
- GPU backends are being introduced deliberately

Expect refactors. Expect breaking changes.

---

## Why This Repository Is Public

Two reasons:

1. Transparency — this is foundational infrastructure and benefits from scrutiny
2. Future reuse — Luna UI is designed to outlive Moth Text

For now, its job is singular:

> Make Moth Text possible.

---

## Final Note

Luna UI exists because the problem demanded it.

Moth Text could not be built correctly on top of existing UI frameworks without unacceptable compromises. Rather than accept those compromises, Luna UI was created.

This repository is where that work happens.
