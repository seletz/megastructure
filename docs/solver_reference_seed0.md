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
sha256: 91f71721334b38f85d3e6bdd17b15b42e37b7a0d09c907e06897b38516b89e05
```

## References

- [[sector-solver]]: the solver and its salts.
- [[tools-and-tasks]]: the task and its script.
