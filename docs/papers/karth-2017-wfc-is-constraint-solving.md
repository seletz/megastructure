---
tags:
  - paper
  - wfc
status: current
authors:
  - Isaac Karth
  - Adam M. Smith
year: 2017
url: https://doi.org/10.1145/3102071.3110566
pdf: link-only
licence: © 2017 ACM; the author-hosted copy carries the ACM notice, which forbids redistribution without permission
---

# WaveFunctionCollapse Is Constraint Solving in the Wild

> [!summary]
> An academic look at Gumin's WFC. The authors show that it is a well-known
> kind of algorithm in disguise: a constraint solver that makes a greedy
> choice, prunes the options that no longer fit, and never backtracks. With
> that framing they test the design choices one by one. A practical finding is
> that the order in which cells are filled matters less than expected: simply
> going row by row works about as well as always picking the most constrained
> cell.

## Citation

Isaac Karth and Adam M. Smith. 2017. WaveFunctionCollapse is Constraint
Solving in the Wild. In *Proceedings of the 12th International Conference on
the Foundations of Digital Games (FDG '17)*, Hyannis, MA, USA. ACM, 10 pages.
DOI: [10.1145/3102071.3110566](https://doi.org/10.1145/3102071.3110566)

Author-hosted copy:
<https://adamsmith.as/papers/wfc_is_constraint_solving_in_the_wild.pdf>

Link only: the copy on the author's site carries the ACM copyright notice
("To copy otherwise, or republish, to post on servers or to redistribute to
lists, requires prior specific permission"), so no PDF is stored here.

## Why it matters here

- It justifies treating the fill solver as an ordinary constraint-propagation
  problem (arc consistency, domain restriction), which is how pre-collapsed
  walkable-graph cells and fixed sector faces are handled.
- Its result that scanline order performs about as well as minimum entropy
  supports using an integer-only heuristic (fewest remaining tiles, hashed
  tie-break) instead of floating-point Shannon entropy, which keeps the solver
  bit-reproducible.

## Used by

- [[RESEARCH_WFC]], section 3 (cell choice) and decision 3 (cell-choice
  heuristic).
