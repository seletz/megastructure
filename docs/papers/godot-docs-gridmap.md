---
tags:
  - paper
  - godot
status: current
authors:
  - Juan Linietsky, Ariel Manzur and the Godot community
year: undated
url: https://docs.godotengine.org/en/stable/classes/class_gridmap.html
pdf: link-only
licence: MIT (Godot class reference); a web page, no PDF
---

# Godot Docs: GridMap

> [!summary]
> The class reference for `GridMap`, Godot's built-in node for building 3D
> levels out of tiles on a grid. Each cell holds a mesh from a `MeshLibrary`
> plus one of 24 right-angle orientations, and the node takes care of drawing
> and collision. Its default cell size of 2 m happens to match the project's
> voxel size.

## Citation

Juan Linietsky, Ariel Manzur and the Godot community. *GridMap*. Godot Engine
class reference (stable), accessed 2026-09-13.
<https://docs.godotengine.org/en/stable/classes/class_gridmap.html>

Link only: a living web page. The class reference is MIT-licensed.

## Why it matters here

GridMap is the planned first way to see and walk on a solved sector: solver
output maps directly onto `set_cell_item()` with an orientation from
`get_orthogonal_index_from_basis()`, and collision comes for free. Its
limits (one draw call per mesh per octant, no per-instance data, no layer
culling) are why placement later moves to `MultiMeshInstance3D`; see
[[godot-docs-multimesh]].

## Used by

- [[RESEARCH_WFC]], section 5 (placement), issue E1 in section 7, and
  decision 5 (GridMap lifetime).
- [[placement]]: `SectorGridMap` places solved sectors with it (#95), with
  the yaw to orientation index table pinned by `mise run gridmap-check`.
