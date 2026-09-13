---
tags:
  - decision
status: accepted
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/issues/36
  - https://github.com/seletz/megastructure/pull/37
  - https://github.com/seletz/megastructure/pull/29
  - "[[PLAN_0.1.0]]"
  - "[[0008-godot-native-rendering-for-the-generative-world]]"
---

# The Ray-Marched Renderer Is a Throwaway Prototype

> [!summary]
> Milestone 0.1.0 draws the chasm with a single fullscreen shader that
> "ray-marches" a mathematical description of the geometry. That renderer
> exists only to get something on screen quickly and to settle how the world
> should look. Later milestones do not build on it; it is expected to be
> deleted once the real, mesh-based world looks as good.

## Context

The HTML prototypes define the look with a ray-marched distance field: every
pixel steps along a ray until it hits a surface described by a formula. PR #29
ported that approach into Godot as a quad in front of the camera. The first
version of the plan described this renderer as something later milestones
would extend. But a distance field cannot easily hold hand-authored tiles,
collision, streaming or Godot's lighting, all of which the generative world
needs.

## Decision

The ray-marcher is a visual prototype and nothing more. Its job is to fly
around in, compare against the HTML page, and tune every constant live. From
milestone 0.2.0 on, the generative world uses Godot's own features instead.
PR #37 corrected the plan accordingly.

## Consequences

- Nothing in the shader port is made production-grade for its own sake.
- Depth compositing with meshes exists for scale checks, not as a bridge to
  the later world.
- What carries over is knowledge: the look, the tuned constants, and the
  shared integer hash.

## Links

- #36, PR #37: plan scope clarified.
- PR #29: the fullscreen ray-march quad.
- [[PLAN_0.1.0]], "Scope".
- Related: [[0008-godot-native-rendering-for-the-generative-world]],
  [[0004-shared-integer-hash-replaces-float-hash]].
