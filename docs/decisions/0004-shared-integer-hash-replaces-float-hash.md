---
tags:
  - decision
status: accepted
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/issues/5
  - https://github.com/seletz/megastructure/pull/30
  - "[[hash_vectors]]"
  - "[[PLAN_0.0.1]]"
---

# Shared Integer Hash Replaces the Float Hash

> [!summary]
> The generator turns a seed and a grid cell into "random" numbers that
> decide where pillars, bridges and openings go. The prototypes did this with
> floating-point tricks whose results depend on the GPU. We replaced it with
> an integer hash that gives exactly the same bits in the shader, in GDScript
> and in the browser, so every part of the project agrees on the layout.

## Context

The prototypes' `h3()` hashed cell coordinates with a float32 `fract()`
formula. Its result depends on how a GPU rounds floats and cannot be
reproduced exactly on the CPU. Game code in GDScript could therefore never
know where the shader had put a pillar, and later generation layers must run
on the CPU.

## Decision

One integer hash of `(seed, cell, salt)`, PCG-style, using 32-bit unsigned
arithmetic only, implemented three times:
[hash.gdshaderinc](../../shaders/include/hash.gdshaderinc),
[hash.gd](../../scripts/hash.gd) and both HTML prototypes (with `Math.imul`).
It returns the top 24 bits divided by 2^24, which float32 holds exactly. Each
call site uses its own salt instead of adding offsets to coordinates. A table
of reference vectors and `mise run hash-vectors` keep the three copies
honest.

## Consequences

- The prototypes' layouts changed once for any given seed. Accepted: the
  prototypes are the reference for the look, not for one arrangement.
- Verified bit-exact on GDScript, Node and a GPU readback (PR #30).
- Every future random decision, including the tile solver, must go through
  this hash, not `RandomNumberGenerator`.

## Links

- #5, PR #30.
- [[hash_vectors]]: definition and reference table.
- [[PLAN_0.0.1#Decision: shared integer hash]].
- Related: [[0011-typed-gdscript-solver-first]].
