---
tags:
  - paper
  - model-synthesis
status: current
authors:
  - Zzyv Zzyzek
year: 2025
url: https://arxiv.org/abs/2501.14786
pdf: local
licence: CC BY 4.0 (arXiv)
---

# Punch Out Model Synthesis

> [!summary]
> A recent refinement of Merrell's block-by-block approach. It fills a large
> grid of tiles by solving one small block at a time, and when a block cannot
> be solved it "punches out" (clears) part of the already-finished area around
> it and tries again, instead of giving up. The paper also introduces a
> "tile correlation length": roughly, how far the influence of one tile
> reaches through the rules. A tile set with a short correlation length can be
> solved in small blocks; a long one needs bigger blocks.

## Citation

Zzyv Zzyzek. 2025. Punch Out Model Synthesis: A Stochastic Algorithm for
Constraint Based Tiling Generation. arXiv:2501.14786 [cs.DC].
<https://arxiv.org/abs/2501.14786>

Local copy: [zzyzek-2025-punch-out-model-synthesis.pdf](pdf/zzyzek-2025-punch-out-model-synthesis.pdf)
(arXiv v1, distributed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)).

## Why it matters here

- The tile correlation length is a practical way to ask "is a 24³ sector big
  enough for this tileset?" If a tile set's rules reach further than a sector,
  fixed faces will make interiors fail, and the fix belongs in the tile set.
- Its erosion step is an alternative to the planned restart-then-degrade
  policy, should restarts turn out to fire often.

## Used by

- [[RESEARCH_WFC]], section 1 (algorithm choice).
