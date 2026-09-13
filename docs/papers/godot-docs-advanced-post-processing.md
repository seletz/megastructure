---
tags:
  - paper
  - godot
status: current
authors:
  - Juan Linietsky, Ariel Manzur and the Godot community
year: undated
url: https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html
pdf: link-only
licence: CC BY 3.0 (Godot documentation); a web page, no PDF
---

# Godot Docs: Advanced Post-Processing

> [!summary]
> A Godot manual page on drawing a shader over the whole screen from inside
> the 3D scene, rather than as a 2D overlay. A flat square mesh is placed so
> that it always covers the camera's view, and its shader can read the depth
> of the scene already drawn. It also explains Godot's "reversed-Z" depth
> convention, in which the near plane is at depth 1 and the far plane at 0.

## Citation

Juan Linietsky, Ariel Manzur and the Godot community. *Advanced
post-processing*. Godot Engine documentation (stable), accessed 2026-09-13.
<https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html>

The documentation is under CC BY 3.0, which would allow a copy, but it is a
living web page rather than a paper, so the note links to it.

## Why it matters here

Milestone 0.1.0 renders the ray-marched chasm exactly this way. A 2×2
`QuadMesh` whose vertex shader sets `POSITION = vec4(VERTEX.xy, 1.0, 1.0)`
covers the screen, a large `extra_cull_margin` keeps it from being culled,
and the fragment shader writes `DEPTH` using the reversed-Z convention, so
ordinary Godot meshes can be composited correctly with the ray-marched
world.

## Used by

- [[PLAN_0.1.0]]: "Fullscreen ray-march quad that composites with scene
  geometry" (#4).
- Code: `vertex()` and the `DEPTH` write in
  [raymarch_world.gdshader](../../shaders/raymarch_world.gdshader),
  `depth_from_world()` in
  [raymarch.gdshaderinc](../../shaders/include/raymarch.gdshaderinc), and
  the `QuadMesh_fullscreen` resource in [main.tscn](../../scenes/main.tscn).
