---
tags:
  - paper
  - sdf
status: current
authors:
  - Inigo Quilez
year: undated
url: https://iquilezles.org/articles/distfunctions/
pdf: link-only
licence: article text and images reserved by the author; code snippets MIT (site-wide notice)
---

# Distance Functions

> [!summary]
> A reference page listing the formulas for signed distance functions (SDFs):
> for a point in space, how far it is from the surface of a sphere, box,
> cylinder and dozens of other shapes, negative inside and positive outside.
> It also lists how to combine shapes (union, subtraction, intersection, and
> smooth blends) and how to repeat, bend or twist them. It is the standard
> recipe book for building scenes that are drawn by ray marching.

## Citation

Inigo Quilez. *Distance Functions*. Web article, iquilezles.org, undated and
continually updated. <https://iquilezles.org/articles/distfunctions/>

Link only: the site states that its code snippets are under the MIT
licence but that the rest is protected, so the article itself is not
copied here.

## Why it matters here

The ray-marched chasm of milestone 0.1.0 is built from these primitives and
operators. The box distance (`sdBox`, `sdBox2`) and the min/max combinations
come straight from this page, and every facade, deck, pillar and bridge in
the chasm is assembled from them.

## Used by

- [[PLAN_0.1.0]]: the ray-marched prototype port.
- Code: [sdf.gdshaderinc](../../shaders/include/sdf.gdshaderinc)
  (`sdSphere`, `sdBox`, `sdBox2`, `opUnion`) and
  [chasm.gdshaderinc](../../shaders/include/chasm.gdshaderinc), which builds
  the chasm from them.
- Prototypes: the `map()` functions in [megastructure.html](../megastructure.html)
  and [megastructure-chasm.html](../megastructure-chasm.html).
- Related: [[quilez-2008-raymarching-distance-fields]].
