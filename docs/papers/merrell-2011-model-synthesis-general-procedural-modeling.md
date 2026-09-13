---
tags:
  - paper
  - model-synthesis
status: current
authors:
  - Paul Merrell
  - Dinesh Manocha
year: 2011
url: https://doi.org/10.1109/TVCG.2010.112
pdf: link-only
licence: © IEEE; the author-hosted PDF has no notice permitting redistribution
---

# Model Synthesis: A General Procedural Modeling Algorithm

> [!summary]
> The journal version of model synthesis. Besides "look like the example", the
> generated model can be made to satisfy extra rules: fixed dimensions, a
> ground plane, connectivity, or large-scale shape constraints set by the
> user. It shows that the same local neighbour rules plus a few global
> constraints can produce whole cities and complex buildings.

## Citation

Paul Merrell and Dinesh Manocha. 2011. Model Synthesis: A General Procedural
Modeling Algorithm. *IEEE Transactions on Visualization and Computer
Graphics* 17, 6, 715–728. Published online 2010.
DOI: [10.1109/TVCG.2010.112](https://doi.org/10.1109/TVCG.2010.112)

Author-hosted PDF:
<https://paulmerrell.org/wp-content/uploads/2021/06/tvcg.pdf>

Link only: IEEE copyright, and the author-hosted copy has no notice permitting
redistribution.

## Why it matters here

The fill layer combines local rules (sockets) with outside constraints that
the solver must respect: walkable-graph cells restricted to floor or stair
tiles, and sector faces fixed in advance. This paper is the most complete
treatment of adding such constraints to model synthesis without a separate
search.

## Used by

- Cited on Merrell's model synthesis page, which [[RESEARCH_WFC]] links in
  section 1. Relevant to the planned pre-collapse step (issue D2 in
  [[RESEARCH_WFC]] section 7).
