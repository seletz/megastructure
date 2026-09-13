---
tags:
  - code-map
  - skeleton
status: current
---

# Skeleton

> [!summary]
> The first layer of the generator: it splits the world into 48 m cubes
> called sectors and gives each one a type (stratum, shaft, cavity, solid or
> chasm). The type is computed from the world seed and the sector's
> coordinates alone, so any sector can be asked about at any time and always
> gets the same answer. The tuning knobs live in one resource; a task prints
> how many sectors of each type seed 0 produces and fails if that changes.
> Nothing draws the sectors yet; the debug renderer comes with issue #77.

## Files

- [sector_grammar.gd](../../scripts/world/sector_grammar.gd)
  (`class_name SectorGrammar`, a `Resource`): every grammar parameter as an
  `@export` field with its default, grouped Lattice, Shaft, Cavity, Solid and
  Chasm. Sizes are in sectors. Out-of-range values are clamped by the reader.
- [skeleton.gd](../../scripts/world/skeleton.gd) (`class_name Skeleton`, a
  `RefCounted`): the `SectorType` enum, the salt constants and
  `sector_type(seed, cell)`.

## Using it

```gdscript
var skeleton := Skeleton.new()                  # default grammar
var type := skeleton.sector_type(WorldState.seed, Vector3i(ix, iy, iz))
print(Skeleton.type_name(type))                 # "shaft"

var grammar := SectorGrammar.new()
grammar.shaft_probability = 0.3
var tuned := Skeleton.new(grammar)
```

`sector_type` runs one private test per rule in precedence order (chasm,
cavity, shaft, solid, else stratum) and returns at the first match. Each test
maps the sector to its coarse cell with floor division, draws a chance with
`Hash.hash3` and integer sizes and offsets with `Hash.hash3_u`, and checks
whether the sector falls inside the run, box or plane placed in that cell.
The rules, their parameters and the salt table (100 to 133) are in
[[sector-skeleton-and-walkable-graph]].

The grammar is a plain resource, not a shader parameter, so the tweak panel
does not show it yet; exposing it belongs to the skeleton viewer (#77).

## How to run or check it

- `mise run skeleton-histogram` prints the seed 0 histogram and checks
  totality, determinism and the reference in [[skeleton_histogram_seed0]]
  ([[tools-and-tasks]]). It is part of `mise run check`.
- After an intended grammar change, `mise run skeleton-histogram --update`
  and commit the regenerated reference.

## References

- [[sector-skeleton-and-walkable-graph]]: the grammar rules, salts and
  parameters.
- [[0015-hashed-multi-scale-sector-grammar]]: why the grammar is hashed on
  coarse cells.
- [[hash]]: the integer hash every decision draws from.
- [[MEGASTRUCTURE_CONCEPT]], section 2.1: the sector types.
