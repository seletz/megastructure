---
tags:
  - moc
status: current
---

# Megastructure Design Wiki

> [!summary]
> This is the starting page of the design wiki for megastructure, a Godot 4
> project that generates an endless Blame!-style structure from a seed. The
> wiki records what we are building, the plan for each milestone, the
> algorithms and papers behind the generator, the decisions we took and why,
> and where each idea lives in the source code. Start with the concept, then
> follow the links. How notes are written is described in [[CONVENTIONS]].

- [[CHANGELOG]]: what changed in each version, newest first.

## Glossary

- [[GLOSSARY]]: plain definitions of the jargon used across the wiki and the
  code. Start here when a term is unfamiliar.

## Concept

- [[MEGASTRUCTURE_CONCEPT]]: design goals, the three-layer generation
  architecture (skeleton, walkable graph, fill), the tile vocabulary taken
  from the prototypes, look and lighting, and the long-term milestones.

## Plan and milestones

- [[PLAN_0.2.0]]: milestone 0.2.0, the generative world: sector skeleton,
  walkable graph, WFC fill with box-only tiles, placement and streaming.
- [[PLAN_0.1.0]]: milestone 0.1.0, the ray-marched chasm prototype ported to
  Godot with a free-fly camera and a live tweak panel.
- Milestones and epics are tracked on
  [GitHub](https://github.com/seletz/megastructure/milestones).

## Research

- [[RESEARCH_WFC]]: how to fill a sector with Wave Function Collapse / model
  synthesis in Godot, with a proposed breakdown of milestone 0.2.0.

## Algorithms

- [[algorithms/README|Algorithm notes]]: one readable note per algorithm:
  the [[integer-hash]], [[sdf-ray-marching]] and the
  [[chasm-distance-field]] behind the current prototype, and
  [[wave-function-collapse]], [[model-synthesis-and-sectors]],
  [[socket-adjacency]], [[sector-skeleton-and-walkable-graph]] and
  [[walkable-graph-connectivity]] for the
  generative world to come.
- [[hash_vectors]]: reference vectors for the shared integer hash.

## Papers and references

- [[papers/README|Papers and references]]: one note per paper, talk or
  documentation page with its citation, a plain-language summary and why it
  matters here. PDFs are stored only where the licence allows it; the index
  says which.

## Decisions

- [[decisions/README|Decision log]]: one dated note per decision with its
  context, the decision and its consequences. Open questions are marked.

## Process

- [[process/README|Process]]: how work becomes a published version:
  [[maintaining]] covers the worktree and pull request tasks, [[releasing]]
  explains versioning, the release task and workflow, and how to verify a
  release. `develop` always carries the next version. [[screenshots]]
  explains how `mise run shot` renders a scene to a PNG without a window.

## Code map

- [[code/README|Code map]]: one note per area of the source tree (camera and
  scene, ray-march shader, hash, tweak UI, tools and tasks, CI and export)
  with what it does, its files and how to run or check it.

## Prototypes

Two self-contained ray-marched HTML pages define the look. Open them in a
browser; Obsidian hands them to the system's default application.

- [megastructure.html](megastructure.html): interior strata, shafts and
  cavities.
- [megastructure-chasm.html](megastructure-chasm.html): the exterior chasm
  between facades, the reference for milestone 0.1.0.
