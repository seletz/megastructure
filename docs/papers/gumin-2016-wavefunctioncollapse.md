---
tags:
  - paper
  - wfc
status: current
authors:
  - Maxim Gumin
year: 2016
url: https://github.com/mxgmn/WaveFunctionCollapse
pdf: link-only
licence: MIT (source code); no paper exists
---

# WaveFunctionCollapse (Gumin)

> [!summary]
> The open-source program that gave Wave Function Collapse (WFC) its name. It
> generates images or tile maps that look like a small example by filling a
> grid one cell at a time: pick the cell with the fewest remaining options,
> choose one, and remove every option in the neighbouring cells that no longer
> fits. It comes in two flavours: an "overlapping" model that learns patterns
> from an example image, and a "simple tiled" model that uses hand-written
> rules about which tiles may sit next to each other. This project uses the
> tiled flavour.

## Citation

Maxim Gumin. *WaveFunctionCollapse*. Source code repository, 2016.
<https://github.com/mxgmn/WaveFunctionCollapse>

There is no accompanying paper; the README is the description. The code is
under the MIT licence. There is no PDF to store; the note links to the
repository.

## Why it matters here

- It is the reference implementation of the *simple tiled model*, the variant
  the concept assumes for the fill layer: tiles, allowed neighbour pairs,
  minimum-entropy cell choice, propagation, restart on contradiction.
- The README's symmetry letters (`X`, `I`, `L`, `T`, `\`, `F`) describe how a
  tile's rotations and mirrors are generated; the planned socket format uses
  the same idea with a `rotations` count.
- The overlapping model is considered and rejected for this project, because
  our tiles are hand-authored meshes rather than patterns learned from an
  example volume.
- Its approach is almost identical to Merrell's earlier model synthesis; see
  [[merrell-2021-comparing-model-synthesis-and-wfc]].

## Used by

- [[RESEARCH_WFC]], sections 1 (algorithm choice), 2 (socket authoring),
  3 (cell choice and propagation) and 6 (reference implementations).
- [[MEGASTRUCTURE_CONCEPT]], section 2.3 (fill layer).
- No code yet; the solver is planned for milestone 0.2.0.
