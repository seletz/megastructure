---
tags:
  - paper
  - godot
  - hash
status: current
authors:
  - Juan Linietsky, Ariel Manzur and the Godot community
year: undated
url: https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html
pdf: link-only
licence: MIT (Godot class reference); a web page, no PDF
---

# Godot Docs: RandomNumberGenerator

> [!summary]
> The class reference for Godot's built-in random number generator. It is
> convenient and seedable, but the documentation warns that the algorithm
> behind it may change between Godot versions: "The underlying algorithm is an
> implementation detail and should not be depended upon". A world that must
> look the same for the same seed forever therefore cannot be built on it.

## Citation

Juan Linietsky, Ariel Manzur and the Godot community. *RandomNumberGenerator*.
Godot Engine class reference (stable), accessed 2026-09-13.
<https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html>

Link only: a living web page. The class reference is MIT-licensed.

## Why it matters here

It is the reason every reproducible decision in the generator, including
every random choice of the planned WFC solver, goes through the project's own
integer hash instead. `RandomNumberGenerator` is fine where reproducibility
across versions does not matter, for example the randomised inputs of the
preset check tool.

## Used by

- [[RESEARCH_WFC]], section 1 (determinism).
- [[hash_vectors]]: the project hash that replaces it for layout decisions.
- Code: [preset_check.gd](../../scripts/tools/preset_check.gd) uses it for
  random test values, where reproducibility is not required.
