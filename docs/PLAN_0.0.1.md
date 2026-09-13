# Plan for milestone 0.0.1: exterior prototype in Godot

Milestone 0.0.1 brings the exterior (chasm) HTML prototype into Godot 4 as a
fullscreen ray-marched scene with a free-fly camera and a live tweak panel.
No gameplay, no streaming, no WFC yet: the goal is pixel parity with
[`megastructure-chasm.html`](megastructure-chasm.html) for the same seed and
camera pose, with every structural and lighting constant exposed as a knob.

The concept and the longer-term architecture (skeleton, walkable graph, WFC
fill) are described in [`MEGASTRUCTURE_CONCEPT.md`](MEGASTRUCTURE_CONCEPT.md).

**Scope.** The ray-marched renderer built here is a throwaway prototype. Its
only job is to get something on screen to fly around in and to settle how the
visuals should look, with every constant adjustable live. It is not the
rendering architecture of the project. From milestone 0.0.2 on, the
three-layer generative approach (skeleton, walkable graph, WFC fill) is built
on Godot's own functionality: meshes, `GridMap`/`MultiMeshInstance3D`, lights,
fog, global illumination and physics. Nothing in this milestone should be
made production-grade for its own sake, and the SDF code is expected to be
dropped once the mesh-based world catches up with it visually.

## Approach

**Fullscreen ray-march quad.** A single `MeshInstance3D` with a `QuadMesh`
and a spatial shader covers the whole view from the near plane. The shader
reconstructs the world-space ray per pixel from the inverse projection and
view matrices, marches the distance field, shades the hit, and writes `DEPTH`
so ordinary Godot meshes intersect and occlude correctly. This keeps the port
a near line-by-line translation of the prototype's GLSL and lets the tweak
panel drive every constant directly. Depth compositing is there so reference
meshes can be dropped into the scene for scale checks, not as a path towards
mixing the SDF with the later mesh-based world.

**Port the chasm distance field feature by feature.** Facades, openings,
pillars, bridges and cables land as separate pull requests, each with a
screenshot next to the HTML prototype at the same seed and camera pose. Every
constant from the prototype becomes a shader uniform whose default equals the
prototype value.

**Free-fly camera.** A `Camera3D` with the prototype's controls: right mouse
drag or captured mouse to look, WASD plus Q/E to move, Shift for speed, mouse
wheel to scale the base speed. The default pose matches the prototype so
screenshots line up.

**Tweak UI.** An in-app panel built from plain Control nodes, generated from a
parameter registry, with seed control, presets and screenshot capture. No
addons.

**Tooling.** Everything runs through mise tasks. CI runs `mise run check` on
pull requests, and the branch workflow is enforced on GitHub.

## Decision: shared integer hash

The prototypes hash cell coordinates with a float32 `fract()`-based `h3()`.
That function depends on GPU float rounding and cannot be reproduced
bit-exactly on the CPU, so GDScript could never agree with the shader about
where a pillar or bridge is.

Milestone 0.0.1 replaces it with an integer hash defined once and implemented
three times: in a shader include using `uint` arithmetic only, in GDScript
using 64-bit ints masked to 32 bits, and in both HTML prototypes using
`Math.imul` and `>>> 0`. A table of reference vectors and a
`mise run hash-vectors` task keep the three implementations honest. See
[#5](https://github.com/seletz/megastructure/issues/5).

The consequence is that the prototypes' layouts change once for a given seed.
That is accepted: the prototypes are the reference for the look, not for a
specific arrangement.

## Epics

Sub-issues land in the order listed. Each issue gets its own branch and
worktree named `<number>-<slug>`, a pull request against `develop`, and a
merge commit after rebase.

### [#1 Rendering pipeline scaffold](https://github.com/seletz/megastructure/issues/1)

Foundation for the exterior prototype: repo docs, a free-fly camera, a
fullscreen ray-marching surface that composites with regular Godot geometry,
and a shared integer hash so Godot and the HTML prototypes agree on layout for
a given seed. Everything else in the milestone builds on this.

- [#2 Add concept docs, prototypes, plan and README](https://github.com/seletz/megastructure/issues/2)
- [#3 Main scene with free-fly camera](https://github.com/seletz/megastructure/issues/3)
- [#4 Fullscreen ray-march quad that composites with scene geometry](https://github.com/seletz/megastructure/issues/4)
- [#5 Shared integer hash for shader, GDScript and the HTML prototypes](https://github.com/seletz/megastructure/issues/5)

### [#6 Chasm geometry port](https://github.com/seletz/megastructure/issues/6)

Port the distance field from the chasm prototype into the fullscreen shader,
feature by feature, with every structural constant exposed as a uniform whose
default equals the prototype value. Depends on the pipeline epic.

- [#7 Facades: wall mass, ledges, decks, buttresses, terraces](https://github.com/seletz/megastructure/issues/7)
- [#8 Openings punched into the facades, with rare lit ones](https://github.com/seletz/megastructure/issues/8)
- [#9 Free-standing pillars with deck rings](https://github.com/seletz/megastructure/issues/9)
- [#10 Bridges spanning the chasm, some broken](https://github.com/seletz/megastructure/issues/10)
- [#11 Hanging cables](https://github.com/seletz/megastructure/issues/11)

### [#12 Look and lighting](https://github.com/seletz/megastructure/issues/12)

Bring the shaded result to parity with the HTML prototype: materials and
grime, key light with soft shadows and ambient occlusion, headlight,
directional fog, tone mapping and post. All coefficients are uniforms with
prototype defaults. Can start against the placeholder SDF but needs the
geometry epic for meaningful screenshots.

- [#13 Surfaces: normals, materials, grime, ambient occlusion](https://github.com/seletz/megastructure/issues/13)
- [#14 Lighting: key light with soft shadows, ambient, headlight, emissive openings](https://github.com/seletz/megastructure/issues/14)
- [#15 Fog, tone mapping, grain, vignette, render scale](https://github.com/seletz/megastructure/issues/15)
- [#16 Marching quality controls and debug views](https://github.com/seletz/megastructure/issues/16)

### [#17 Tweak UI](https://github.com/seletz/megastructure/issues/17)

An in-app panel to adjust every knob live, manage seeds and presets, and
capture screenshots for comparison with the prototypes. GDScript, Control
nodes, no addons.

- [#18 Parameter registry and auto-generated panel](https://github.com/seletz/megastructure/issues/18)
- [#19 Seed control](https://github.com/seletz/megastructure/issues/19)
- [#20 Presets: save, load, prototype defaults](https://github.com/seletz/megastructure/issues/20)
- [#21 HUD and screenshots](https://github.com/seletz/megastructure/issues/21)

### [#22 Tooling and CI](https://github.com/seletz/megastructure/issues/22)

Keep the build automated with mise and enforce the branch workflow on GitHub.

- [#23 GitHub Actions: run mise check on pull requests](https://github.com/seletz/megastructure/issues/23)
- [#24 Export preset and export-template task](https://github.com/seletz/megastructure/issues/24)
- [#25 Repository merge settings and branch protection](https://github.com/seletz/megastructure/issues/25)

## Comparing with the HTML prototype

Press F1 in the Godot build to show the HUD (FPS, frame time, camera position,
yaw/pitch, seed) and F12 to save a screenshot, without HUD and tweak panel, to
`user://screenshots/<seed>_<yyyymmdd-hhmmss>.png`; the absolute path is printed
to the console. To render the same view in `docs/megastructure-chasm.html` (or
`docs/megastructure.html`):

- **Same seed.** The prototypes take an integer seed in `state.seed`. Open the
  browser's developer console and run `state.seed = N` with the seed from the
  HUD, or edit the initial value in the `state` object in the file.
- **Same pose.** Set `state.pos = [x, y, z]`, `state.yaw` and `state.pitch` to
  the HUD values. Since #34 the Godot camera uses the prototype's yaw/pitch
  convention (yaw 0 looks toward +Z), so the numbers carry over unchanged.
- **Resolution.** The Godot render runs at half resolution by default
  (`rendering/scaling_3d/scale = 0.5`) and is upscaled to the window, so match
  the browser window size and expect softer detail unless the render scale is
  raised to 1.0.

## Done when

- `mise run run` starts into the chasm with the prototype's default camera
  pose, and the image matches the HTML prototype for the same seed.
- Every prototype constant is adjustable from the tweak panel, and presets
  reproduce the prototype defaults.
- `mise run check` passes locally and in CI on every pull request.
