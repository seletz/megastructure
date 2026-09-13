---
tags:
  - decision
status: accepted
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/issues/71
  - https://github.com/seletz/megastructure/issues/15
  - "[[raymarch-shader]]"
  - "[[sdf-ray-marching]]"
---

# Film Grain Off by Default

> [!summary]
> The film grain in the shader's post chain now starts switched off. At the
> project's half render resolution each grain speck covers a 2x2 block of
> screen pixels and changes 24 times a second, so the image looked covered in
> snow rather than film. The grain setting stays available and can be turned
> back on.

## Context

The post chain (#15) ported the prototype's grain: `grain_amount` 0.04,
hashed per render pixel and re-rolled at `grain_fps` 24. The prototype draws
at full resolution, but `project.godot` sets `rendering/scaling_3d/scale` to
0.5. After the first play session the grain was reported as snow (#71).
The shader cannot see the output pixel grid, so the grain cannot simply be
hashed at screen resolution.

## Decision

- `grain_amount` defaults to 0.0 in
  [post.gdshaderinc](../../shaders/include/post.gdshaderinc), with a comment
  giving the reason.
- The knob, `grain_fps` and the grain code stay; the tweak panel and presets
  can still turn grain on. Grain is meant for full-resolution renders.
- With grain off the image has no other time-dependent input: two
  consecutive frames of seed 1 at the default pose were checked to be
  byte-identical, and with grain at 0.04 about 90 % of pixels differed.

## Consequences

- The default image is stable from frame to frame; `seed-check` keeps
  comparing frames byte for byte.
- A preset saved with grain on still applies it, including at half
  resolution.
- If grain is wanted at a reduced render scale, it needs a different
  approach, such as scaling the amount by the render scale or applying it
  after upscaling.

## Links

- #71 (this change), #15 (post chain).
- [[raymarch-shader]], [[sdf-ray-marching]], [[0003-ray-marcher-is-a-throwaway-prototype]].
