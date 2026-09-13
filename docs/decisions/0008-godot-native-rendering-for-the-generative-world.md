---
tags:
  - decision
status: accepted
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/issues/36
  - https://github.com/seletz/megastructure/pull/37
  - https://github.com/seletz/megastructure/pull/42
  - "[[PLAN_0.1.0]]"
  - "[[RESEARCH_WFC]]"
  - "[[0003-ray-marcher-is-a-throwaway-prototype]]"
---

# Godot-Native Rendering for the Generative World

> [!summary]
> From milestone 0.2.0 on, the generated megastructure is made of ordinary
> Godot objects: tile meshes placed on a grid, Godot's lights, fog and
> physics. We do not write our own renderer. This lets the world have
> collision, streaming and level of detail using features the engine already
> has.

## Context

The world is generated in three layers: a skeleton of 48 m sectors, a
walkable graph, and a fill of hand-authored tiles on a 2 m grid
([[MEGASTRUCTURE_CONCEPT]]). The 0.1.0 ray-marcher can draw formulas, but not
placed tiles the player can walk on
([[0003-ray-marcher-is-a-throwaway-prototype]]).

## Decision

Build the generative world on Godot features, as set out in the plan's
"Scope" and in [[RESEARCH_WFC]], section 5:

- Placement first with `GridMap` for a quick walkable sector, then one
  `MultiMeshInstance3D` per tile mesh and sector for streaming.
- Collision from GridMap early, later one static trimesh per sector.
- Forward+ with exponential fog and a headlight; no global illumination at
  first, SDFGI evaluated in the look pass.
- Visibility ranges and a per-sector impostor for distance; occluders built
  from solid cells.
- Worker threads produce plain data; the main thread creates nodes.

## Consequences

- The distance-field shader code is not extended and will be removed once the
  mesh world catches up visually.
- Engine limits apply, such as GridMap's draw calls per mesh; the research
  plans the MultiMesh switch for that reason.
- The shared integer hash and the tuned look are what carry over.

## Links

- #36, PR #37: plan scope; PR #42: WFC research.
- [[PLAN_0.1.0]], "Scope"; [[RESEARCH_WFC]], "5. Placement in Godot".
- Related: [[0011-typed-gdscript-solver-first]].
