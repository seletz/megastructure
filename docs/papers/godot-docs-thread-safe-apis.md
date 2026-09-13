---
tags:
  - paper
  - godot
status: current
authors:
  - Juan Linietsky, Ariel Manzur and the Godot community
year: undated
url: https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html
pdf: link-only
licence: CC BY 3.0 (Godot documentation); a web page, no PDF
---

# Godot Docs: Thread-Safe APIs

> [!summary]
> A Godot manual page listing what code running on a background thread may
> and may not touch. The scene tree is off limits; building nodes that are
> not yet in the tree is allowed; the rendering and physics servers are only
> safe from threads when special project settings are on; arrays and
> dictionaries can be read and written but not resized from several threads
> at once.

## Citation

Juan Linietsky, Ariel Manzur and the Godot community. *Thread-safe APIs*.
Godot Engine documentation (stable), accessed 2026-09-13.
<https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html>

The documentation is under CC BY 3.0; it is a living web page, so the note
links to it.

## Why it matters here

It sets the contract for sector jobs: a worker produces only plain data
(tile ids, a `PackedFloat32Array` MultiMesh buffer per tile, collision faces
as a `PackedVector3Array`), and the main thread makes the few bulk calls that
go through `RenderingServer` and `PhysicsServer3D`, such as assigning
`MultiMesh.buffer` or `ConcavePolygonShape3D.set_faces()`.

## Used by

- [[RESEARCH_WFC]], section 4 (threads).
- Related: [[godot-docs-workerthreadpool]], [[godot-docs-multimesh]].
- No code yet; planned for milestone 0.2.0.
