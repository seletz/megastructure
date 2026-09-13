---
tags:
  - skeleton
  - reference
status: current
---

# Skeleton Histogram, Seed 0

> [!summary]
> How many sectors of each type the skeleton produces in the 9 × 9 × 9
> sectors centred on the origin for seed 0, per horizontal layer and in
> total. `mise run skeleton-histogram` recomputes the table and fails if it
> differs, so a change to the grammar or its defaults that changes the world
> shows up here. After an intended change, regenerate this file with
> `mise run skeleton-histogram --update` and commit it.

Cells span x, y and z from -4 to 4 with the default `SectorGrammar`.
Generated file: only the table rows are compared.

| y | stratum | shaft | cavity | solid | chasm |
| ---: | ---: | ---: | ---: | ---: | ---: |
| -4 | 46 | 10 | 11 | 14 | 0 |
| -3 | 46 | 10 | 11 | 14 | 0 |
| -2 | 0 | 0 | 0 | 81 | 0 |
| -1 | 46 | 10 | 11 | 14 | 0 |
| 0 | 0 | 0 | 0 | 81 | 0 |
| 1 | 40 | 8 | 12 | 21 | 0 |
| 2 | 40 | 8 | 12 | 21 | 0 |
| 3 | 40 | 8 | 12 | 21 | 0 |
| 4 | 0 | 0 | 0 | 81 | 0 |
| **all** | 258 | 54 | 69 | 348 | 0 |

## References

- [[sector-skeleton-and-walkable-graph]]: the grammar these counts come from.
- [[tools-and-tasks]]: the task and its script.
