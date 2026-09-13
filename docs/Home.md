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

## Concept

- [[MEGASTRUCTURE_CONCEPT]]: design goals, the three-layer generation
  architecture (skeleton, walkable graph, fill), the tile vocabulary taken
  from the prototypes, look and lighting, and the long-term milestones.

## Plan and milestones

- [[PLAN_0.0.1]]: milestone 0.0.1, the ray-marched chasm prototype ported to
  Godot with a free-fly camera and a live tweak panel.
- Milestones and epics are tracked on
  [GitHub](https://github.com/seletz/megastructure/milestones).

## Research

- [[RESEARCH_WFC]]: how to fill a sector with Wave Function Collapse / model
  synthesis in Godot, with a proposed breakdown of milestone 0.0.2.

## Algorithms

- [[hash_vectors]]: the shared integer hash that drives every layout
  decision, implemented identically in the shader, GDScript and the
  prototypes, with reference vectors.
- Algorithm notes (planned in #58): one note per algorithm, such as the
  sector grammar, the walkable graph and the WFC solver.

## Papers and references

- Papers library (planned in #57): one note per paper or reference with its
  citation, a summary, and the PDF where the licence allows it.
- Until then, references are cited inline in [[RESEARCH_WFC]].

## Decisions

- Decision log (planned in #59): one note per decision in ADR style.
- Decisions already recorded in existing documents:
  - [[PLAN_0.0.1#Decision: shared integer hash]]
  - [[RESEARCH_WFC#Decisions to make]] (open)

## Code map

- Code map (planned in #60): where each concept lives in the source tree,
  with relative links into `scripts/`, `shaders/` and `scenes/`.

## Prototypes

Two self-contained ray-marched HTML pages define the look. Open them in a
browser; Obsidian hands them to the system's default application.

- [megastructure.html](megastructure.html): interior strata, shafts and
  cavities.
- [megastructure-chasm.html](megastructure-chasm.html): the exterior chasm
  between facades, the reference for milestone 0.0.1.
