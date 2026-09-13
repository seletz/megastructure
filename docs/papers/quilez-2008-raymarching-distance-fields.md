---
tags:
  - paper
  - sdf
status: current
authors:
  - Inigo Quilez
year: 2008
url: https://iquilezles.org/articles/raymarchingdf/
pdf: link-only
licence: article text and images reserved by the author; code snippets MIT (site-wide notice)
---

# Raymarching Distance Fields

> [!summary]
> An introduction to ray marching signed distance fields and its history. To
> draw a pixel, start at the camera and step along the ray; at each point the
> distance function tells how far the nearest surface is, so the ray can
> safely jump that far. When the distance becomes tiny, the ray has hit
> something. Because the scene is a formula rather than a mesh, effects like
> soft shadows and ambient occlusion can be computed by querying the same
> function again. The page links Quilez's talks and examples on the topic.

## Citation

Inigo Quilez. *Raymarching Distance Fields*. Web article, iquilezles.org,
2008. <https://iquilezles.org/articles/raymarchingdf/>

Link only: the site states that its code snippets are under the MIT
licence but that the rest is protected, so the article itself is not
copied here.

## Why it matters here

Milestone 0.1.0 renders the whole world this way: one fullscreen shader
marches the chasm's distance function. Besides the march loop, the
five-sample ambient occlusion (sample the distance function at growing
offsets along the normal and darken where geometry is closer than expected)
follows the approach popularised in Quilez's ray-marching work. The concept
also keeps open the option of ray-marched impostors for distant sectors.

## Used by

- [[PLAN_0.1.0]]: the fullscreen ray-march quad and marching quality
  controls.
- [[MEGASTRUCTURE_CONCEPT]]: open question on SDF impostors for distant
  sectors.
- Code: the march loop in
  [raymarch_world.gdshader](../../shaders/raymarch_world.gdshader), ray setup
  in [raymarch.gdshaderinc](../../shaders/include/raymarch.gdshaderinc), and
  ambient occlusion in
  [surface.gdshaderinc](../../shaders/include/surface.gdshaderinc).
- Related: [[quilez-distance-functions]], [[quilez-2010-soft-shadows]],
  [[quilez-2015-sdf-normals]], [[quilez-2010-better-fog]].
