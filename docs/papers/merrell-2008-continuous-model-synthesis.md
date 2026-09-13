---
tags:
  - paper
  - model-synthesis
status: current
authors:
  - Paul Merrell
  - Dinesh Manocha
year: 2008
url: https://doi.org/10.1145/1409060.1409111
pdf: link-only
licence: © ACM; the author-hosted PDF has no notice permitting redistribution
---

# Continuous Model Synthesis

> [!summary]
> A follow-up to model synthesis that drops the regular grid. Instead of
> fixed-size cubes, the example model is cut along its own planes, so the
> output can have walls and roofs at any position and angle while still
> resembling the input. The examples are buildings, roads and other man-made
> structures generated in minutes.

## Citation

Paul Merrell and Dinesh Manocha. 2008. Continuous Model Synthesis. *ACM
Transactions on Graphics* 27, 5 (SIGGRAPH Asia 2008).
DOI: [10.1145/1409060.1409111](https://doi.org/10.1145/1409060.1409111)

Author-hosted PDF:
<https://paulmerrell.org/wp-content/uploads/2021/06/continuous.pdf>

Link only: ACM copyright, and the author-hosted copy has no notice permitting
redistribution.

## Why it matters here

Background rather than a direct input. The fill layer deliberately stays on
a regular 2 m grid, which is what makes sockets, bitset propagation and
`GridMap`/`MultiMesh` placement simple. This paper is the reference if the
tile vocabulary ever needs geometry that does not snap to the grid, for
example the slanted buttresses of the prototypes.

## Used by

- Cited on Merrell's model synthesis page, which [[RESEARCH_WFC]] links in
  section 1. No note or code uses it directly yet.
