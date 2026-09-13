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
| -4 | 51 | 18 | 0 | 12 | 0 |
| -3 | 45 | 14 | 10 | 12 | 0 |
| -2 | 35 | 10 | 10 | 26 | 0 |
| -1 | 55 | 2 | 10 | 14 | 0 |
| 0 | 64 | 2 | 0 | 15 | 0 |
| 1 | 57 | 7 | 6 | 11 | 0 |
| 2 | 52 | 13 | 6 | 10 | 0 |
| 3 | 51 | 16 | 2 | 12 | 0 |
| 4 | 49 | 17 | 2 | 13 | 0 |
| **all** | 459 | 99 | 46 | 125 | 0 |

## References

- [[sector-skeleton-and-walkable-graph]]: the grammar these counts come from.
- [[tools-and-tasks]]: the task and its script.
