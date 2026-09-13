---
tags:
  - paper
  - model-synthesis
status: current
authors:
  - Paul Merrell
year: 2007
url: https://doi.org/10.1145/1230100.1230119
pdf: link-only
licence: © ACM; the author-hosted PDF has no notice permitting redistribution. The code repository is MIT.
---

# Example-Based Model Synthesis

> [!summary]
> The paper that introduced model synthesis, nine years before WFC. From a
> small hand-made 3D model it builds a much larger model that looks similar,
> by placing pieces on a grid so that every pair of neighbours also appears
> somewhere in the example. Its key trick for large outputs is to change the
> model one small block at a time, starting from a model that is already valid
> and keeping the block's border fixed; a block that fails is simply tried
> again. Merrell later published the code under the MIT licence.

## Citation

Paul Merrell. 2007. Example-Based Model Synthesis. In *Proceedings of the 2007
Symposium on Interactive 3D Graphics and Games (I3D '07)*. ACM, 105–112.
DOI: [10.1145/1230100.1230119](https://doi.org/10.1145/1230100.1230119)

- Author-hosted PDF:
  <https://paulmerrell.org/wp-content/uploads/2022/03/model_synthesis.pdf>
- Project page: <https://paulmerrell.org/model-synthesis/>
- Code: [merrell42/model-synthesis](https://github.com/merrell42/model-synthesis)
  (C++, MIT for the files outside `third_party`).

Link only: the publisher version is ACM copyright and the author-hosted PDF
carries no notice permitting redistribution.

## Why it matters here

- "Modify in blocks" is the scaling fix for plain WFC, whose chance of failure
  grows with output size. A 48 m sector solved with fixed faces over an
  implicit all-solid world is one such block step.
- "Start from a trivially valid state" is why the tileset has a universal
  `solid` tile: an all-solid interior is always a valid fallback, so a failed
  sector can degrade deterministically instead of breaking its neighbours.
- The repository's AC-4 and AC-3 propagators are a structural reference for
  the planned GDScript solver.

## Used by

- [[RESEARCH_WFC]], section 1 (algorithm choice), section 3 (failure model)
  and section 6 (reference implementations).
- [[walkable-graph-connectivity]]: regions with fixed boundary edges, in the
  spirit of solving in blocks.
- Related: [[merrell-2009-model-synthesis-thesis]],
  [[merrell-2021-comparing-model-synthesis-and-wfc]].
