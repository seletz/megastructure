---
tags:
  - paper
  - godot
status: current
authors:
  - Juan Linietsky, Ariel Manzur and the Godot community
year: undated
url: https://docs.godotengine.org/en/stable/classes/class_multimesh.html
pdf: link-only
licence: MIT (Godot class reference); a web page, no PDF
---

# Godot Docs: MultiMesh

> [!summary]
> The class reference for `MultiMesh`, which draws many copies of the same
> mesh in one go, each with its own position and rotation. The GPU receives
> one mesh and a list of transforms instead of thousands of separate objects,
> which makes it the standard way to draw large numbers of identical tiles.
> It is shown in the scene by a `MultiMeshInstance3D` node.

## Citation

Juan Linietsky, Ariel Manzur and the Godot community. *MultiMesh*. Godot
Engine class reference (stable), accessed 2026-09-13.
<https://docs.godotengine.org/en/stable/classes/class_multimesh.html>

See also *MultiMeshInstance3D*:
<https://docs.godotengine.org/en/stable/classes/class_multimeshinstance3d.html>

Link only: living web pages. The class reference is MIT-licensed.

## Why it matters here

- The planned streaming placement uses one `MultiMeshInstance3D` per tile
  mesh per sector: about twenty nodes and one draw call each. Rotated tile
  variants share a MultiMesh because the rotation goes into the instance
  transform.
- Transforms are uploaded in one `PackedFloat32Array` through `buffer`, built
  on a worker thread. The class reference does not document that buffer's
  float layout, so the placement issue must verify it and pin it with a test.
- Setting `custom_aabb` to the sector box avoids recomputing bounds.

## Used by

- [[RESEARCH_WFC]], section 5 (placement) and issues E2 to E4 in section 7.
- Related: [[godot-docs-gridmap]], [[godot-docs-workerthreadpool]].
- No code yet; placement is planned for milestone 0.2.0.
