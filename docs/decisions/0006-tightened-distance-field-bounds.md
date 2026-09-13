---
tags:
  - decision
status: accepted
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/pull/33
  - https://github.com/seletz/megastructure/pull/39
  - https://github.com/seletz/megastructure/pull/41
  - https://github.com/seletz/megastructure/pull/43
  - "[[0003-ray-marcher-is-a-throwaway-prototype]]"
---

# Distance-Field Bounds Tightened Versus the Prototype

> [!summary]
> A ray-marcher moves along each ray in steps as large as the distance field
> says is safe. If the field overestimates that distance, rays jump into
> walls, and the image shows streaks, fins or missing holes. Where the
> prototype's formulas overestimated, the Godot port corrects them so the
> field is a true lower bound, while keeping the same layout for a given seed.

## Context

A direct port of `facade()` from
[megastructure-chasm.html](../megastructure-chasm.html) showed dark, wavy
streaks near buttress and terrace borders (PR #33), and openings that did not
render at all (PR #39).

## Decision

Deviate from the prototype's formulas wherever they are not safe bounds, in
[chasm.gdshaderinc](../../shaders/include/chasm.gdshaderinc):

- **Buttress removal:** a removed cell also checks the three neighbouring
  cells towards the nearest corner and bounds any buttress piece they keep.
- **Terrace borders:** neighbours are bounded by their actual recess and
  profiles instead of a generic 10 m slab (PR #33), and by the opening punched
  at their own depth (PR #39).
- **Openings:** the cut-out box extends into the void in front of the wall,
  so the field is no longer zero across the hole mouth (PR #39).
- Pillars and bridges likewise check the neighbour cell towards the nearer
  border (PRs #41, #43).

## Consequences

- Close-ups of the affected borders render cleanly; which features exist is
  unchanged.
- The shader no longer matches the prototype line by line; the pull requests
  document each deviation.
- Neighbour checks cost extra evaluations per step. Acceptable for a
  throwaway renderer.

## Links

- PR #33 (buttress and terrace), PR #39 (openings), PRs #41 and #43.
- Related: [[0003-ray-marcher-is-a-throwaway-prototype]],
  [[0007-keep-overlaid-facade-layouts]].
