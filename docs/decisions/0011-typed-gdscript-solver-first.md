---
tags:
  - decision
status: proposed
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/pull/42
  - "[[RESEARCH_WFC]]"
  - "[[0010-near-universal-solid-tile-with-seeded-restarts]]"
---

# Typed GDScript Solver First, Native Extension Only Past a Measured Threshold

> [!note] Proposed
> Recommended by the research, not yet decided. The threshold is a proposal
> to confirm once benchmark numbers exist.

> [!summary]
> The tile solver is the one piece of code where speed may matter. We propose
> to write it first in GDScript, Godot's own scripting language, with static
> types and compact data, and to measure it. Only if one sector takes longer
> than a set limit does the solver move to compiled native code, behind the
> same interface.

## Context

GDScript is interpreted and slowest in tight numeric loops, which is what a
solver's propagation step is. The research estimates 0.5 to 3 seconds per
sector in typed GDScript, marginal for streaming ([[RESEARCH_WFC]],
section 4). A native extension (Rust or C++) could be 20 to 100 times faster,
but adds a toolchain and a compile step. No existing Godot addon fits the
tile authoring model.

## Decision

Proposed:

- Write the solver fresh in typed GDScript, about 500 lines, with domains as
  64-bit bitsets in packed arrays.
- Keep it behind `SectorSolver.solve()`: packed arrays in, a tile index per
  cell out.
- Add a benchmark task; move only `solve()` to a GDExtension if a stratum
  sector takes more than 1 second.
- Draw every random choice from the shared integer hash, so a native port
  gives bit-identical results.

## Consequences

- No extra toolchain until the numbers demand one; if it comes, mise pins it.
- C# is not an intermediate step: it adds .NET without removing the compile
  cost.

## Links

- PR #42; [[RESEARCH_WFC]], "4. Performance in Godot 4", "6. Existing addons"
  and "Decisions to make", item 4.
- Related: [[0004-shared-integer-hash-replaces-float-hash]],
  [[0001-all-automation-through-mise]].
