---
tags:
  - solver
  - reference
status: current
---

# Solver Reference, Seed 0

> [!summary]
> The SHA-256 of the tiles `SectorSolver` places in an unconstrained 8 × 8 × 8
> grid with the placeholder tileset at seed 0, sector (0, 0, 0), with the
> default minimum remaining values heuristic. `mise run solver-check`
> recomputes it and fails if it differs, so any change to the solver, the
> hash, the tileset or the adjacency table that changes the output shows up
> here. After an intended change, regenerate this file with
> `mise run solver-check --update` and commit it.

The digest covers `Result.cells` as little-endian int32 tile indices in cell
order `x + 8 * (y + 8 * z)`. Generated file: only the `sha256:` line is
compared.

```
sha256: 1d9e211ea5ed8773416a09f3ad2a6e918fba45dfd0c6491b475d7d38b4251d6a
```

## References

- [[sector-solver]]: the solver and its salts.
- [[tools-and-tasks]]: the task and its script.
