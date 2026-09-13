---
tags:
  - code-map
  - rendering
status: current
---

# Ray-March Shader

> [!summary]
> One shader draws the entire world. For every pixel it sends a ray from the
> camera into a mathematical description of the chasm and steps along it until
> it touches a surface. It then works out which way that surface faces, what
> it is made of (concrete, metal or a lit window), how much light and shadow
> it gets, and how much fog lies in between, and finishes with a film-like
> tone curve, grain and vignette. The shader is split into a main file and
> small include files, one per job. Every tunable number is a uniform, which
> the tweak panel picks up automatically.

## Files and what each does

The main shader is
[raymarch_world.gdshader](../../shaders/raymarch_world.gdshader). It pulls in
the includes in dependency order:

| Include | Job |
| --- | --- |
| [sdf.gdshaderinc](../../shaders/include/sdf.gdshaderinc) | Distance formulas for basic shapes: `sdSphere`, `sdBox`, the 2D `sdBox2`, and `opUnion`. |
| [raymarch.gdshaderinc](../../shaders/include/raymarch.gdshaderinc) | Camera maths: the world-space ray through a pixel, the near-plane distance, and turning a hit point into a depth value (Godot uses reversed-Z, so near is 1 and far is 0). |
| `hash.gdshaderinc` | The shared integer hash and the `seed` uniform; described in [[hash]]. |
| [chasm.gdshaderinc](../../shaders/include/chasm.gdshaderinc) | The world itself: `chasm_map()` returns the distance to the nearest facade, pillar, bridge or cable and its material id. |
| [surface.gdshaderinc](../../shaders/include/surface.gdshaderinc) | Albedo per material with hashed grime, and ambient occlusion (`surface_ao`). |
| [lighting.gdshaderinc](../../shaders/include/lighting.gdshaderinc) | Key light with soft shadows, sky and ground ambient, a camera headlight, and the glow of lit openings (`lighting_shade`). |
| [post.gdshaderinc](../../shaders/include/post.gdshaderinc) | Height-graded fog (`post_fog_color`, `post_apply_fog`) and the post chain: exposure tone map, grain and vignette (`post_process`). |

The main shader declares `map()` (distance plus material) and
`map_distance()` (distance only) between the chasm include and the surface
and lighting includes, because ambient occlusion and shadows sample the world
too.

## The marching loop

The vertex shader places the quad's corners at the screen corners, so the
fragment shader runs once per pixel. `fragment()` then:

1. Builds the ray from `CAMERA_POSITION_WORLD` through the pixel and starts it
   at the near plane, so a hit never lands on the camera.
2. Checks whether the camera sits inside solid geometry. If so, the ray first
   steps out of it, the way a camera clipping into a mesh sees through it.
3. Repeats up to `max_steps` times: ask `map()` how far the nearest surface
   is, stop if that is below the hit threshold (`hit_epsilon` scaled by the
   distance travelled), otherwise advance by that distance times
   `step_scale`. It gives up past `max_distance`.
4. Writes `DEPTH` for a hit (misses go to the far plane), so ordinary meshes
   and the ray-marched world hide each other correctly.
5. For a hit: computes the normal from four samples of `map_distance()`
   around the point (`calc_normal`, with the offset `normal_epsilon`), then
   ambient occlusion, albedo, lighting and fog. For a miss: the fog colour
   along the ray. Either way the result goes through `post_process()`.
   Its film grain is off by default (`grain_amount` 0.0): at half render
   resolution it flickers in 2x2 blocks
   ([[0013-film-grain-off-by-default]]).

The tuning uniforms for this loop are in the `marching` group.

## Materials

`chasm_map()` reports one of three material ids, defined in the chasm
include: `CHASM_MAT_CONCRETE` (walls, ledges, pillars), `CHASM_MAT_METAL`
(bridges and cables) and `CHASM_MAT_LIT` (the inside of a lit opening).
Surface picks the concrete or metal albedo, lighting adds the emissive colour
for lit openings.

## Debug views

The `debug_view` uniform (group `debug`) switches the output. Debug views skip
lighting, fog and post processing, but still write depth.

| Value | View | Shows |
| --- | --- | --- |
| 0 | Shaded | The normal image. |
| 1 | Steps | Marching steps per pixel as a blue-green-yellow-red heat map; red means the ray used up `max_steps`. |
| 2 | Depth | Hit distance as grey, misses white. |
| 3 | Normals | Surface normal as colour, misses black. |
| 4 | Material | Grey concrete, blue metal, orange lit; misses black. |

## Uniform groups

Each include declares its uniforms inside `group_uniforms` blocks: `chasm`
with sub-groups `ledges`, `decks`, `buttresses`, `terraces`, `openings`,
`pillars`, `bridges` and `cables`; `surface` with `grime` and `ao`;
`lighting` with `shadow`, `headlight` and `emissive`; `fog`; `post`;
`marching`; `debug`. These groups become the sections of the tweak panel
([[tweak-ui]]); `vec3` uniforms such as the colours and the key light
direction are not shown there yet. `mise run ui-params` prints them with their ranges and
defaults.

## How to run or check it

- `mise run run` and open the panel with Tab to change uniforms live; set
  `debug_view` to Steps to see where rays run out of steps.
- `mise run ui-params` lists every uniform the panel discovers.
- `mise run check` compiles the scripts and loads the project, which also
  loads the shader; `mise run seed-check` renders frames and compares them
  ([[tools-and-tasks]]).
- The look is judged against `docs/megastructure-chasm.html`, which the
  includes were ported from.

## References

- [[sdf-ray-marching]]: distance fields, sphere tracing, normals, AO and soft
  shadows.
- [[chasm-distance-field]]: how the chasm include builds facades, openings,
  pillars, bridges and cables from hashed cells.
- [[integer-hash]]: the hash every layout decision uses.
- [[0003-ray-marcher-is-a-throwaway-prototype]],
  [[0006-tightened-distance-field-bounds]],
  [[0007-keep-overlaid-facade-layouts]] and
  [[0013-film-grain-off-by-default]]: decisions about this shader.
- [[camera-and-scene]]: the quad the shader is drawn on.
- Papers: [[quilez-2008-raymarching-distance-fields]],
  [[quilez-distance-functions]], [[quilez-2015-sdf-normals]],
  [[quilez-2010-soft-shadows]], [[quilez-2010-better-fog]].
