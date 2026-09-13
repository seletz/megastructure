---
tags:
  - paper
  - wfc
status: current
authors:
  - Mathieu Fehr
year: 2018
url: https://github.com/math-fehr/fast-wfc
pdf: link-only
licence: MIT (files under src/)
---

# fast-wfc

> [!summary]
> A C++ implementation of WFC written for speed. It supports both of Gumin's
> models, and its optimisations, largely in how the data is laid out in
> memory, made it about ten times faster than the implementations available
> when it appeared.

## Citation

Mathieu Fehr. *fast-wfc: An implementation of Wave Function Collapse with a
focus on performance*. C++ source code, 2018 onwards.
<https://github.com/math-fehr/fast-wfc>

The source files directly under `src/` are MIT. No paper; link only.

## Why it matters here

It is the reference if the solver has to move from GDScript to a native
GDExtension. The research note sets the threshold at more than one second per
stratum sector in the benchmark task, and expects a 20 to 100 times speed-up
from a native propagator with a good data layout.

## Used by

- [[RESEARCH_WFC]], section 4 (when to go native) and section 6 (reference
  implementations).
