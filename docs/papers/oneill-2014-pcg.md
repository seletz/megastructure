---
tags:
  - paper
  - hash
status: current
authors:
  - Melissa E. O'Neill
year: 2014
url: https://www.pcg-random.org/paper.html
pdf: link-only
licence: © 2014 Melissa O'Neill; no notice permitting redistribution
---

# PCG: A Family of Random Number Generators

> [!summary]
> The paper behind PCG, a family of random number generators that are small,
> fast and statistically good. The recipe is to take a very simple and fast
> generator (a linear congruential generator, which on its own has visible
> patterns) and pass each output through a cheap scrambling step that hides
> those patterns. That scrambling step, used on its own as a hash, is what
> this project calls `pcg`.

## Citation

Melissa E. O'Neill. 2014. *PCG: A Family of Simple Fast Space-Efficient
Statistically Good Algorithms for Random Number Generation*. Technical Report
HMC-CS-2014-0905, Harvey Mudd College, Claremont, CA.
<https://www.cs.hmc.edu/tr/hmc-cs-2014-0905.pdf>

Paper page with history and errata: <https://www.pcg-random.org/paper.html>

Link only: the report reads "Copyright 2014, Melissa O'Neill" and has no
notice permitting redistribution.

## Why it matters here

Every layout decision in the world (where a column is missing, where a bridge
spans the chasm, how much grime a surface has, and later every tile choice in
the WFC solver) comes from one integer hash built from the PCG output
permutation. The paper explains why that permutation mixes bits well enough.
The GPU-specific evaluation that picked it is
[[jarzynski-2020-hash-functions-gpu-rendering]].

## Used by

- [[hash_vectors]]: the definition of `pcg` and `hash3_u`.
- [[PLAN_0.0.1]], decision "shared integer hash".
- Code: [hash.gdshaderinc](../../shaders/include/hash.gdshaderinc),
  [hash.gd](../../scripts/hash.gd), and the `pcg()` functions in
  [megastructure.html](../megastructure.html) and
  [megastructure-chasm.html](../megastructure-chasm.html).
