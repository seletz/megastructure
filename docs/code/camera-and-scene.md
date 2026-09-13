---
tags:
  - code-map
status: current
---

# Camera and Scene

> [!summary]
> The whole program is one Godot scene with very little in it: a camera you
> fly with the mouse and keyboard, a flat rectangle glued to the front of that
> camera, a dark background, and two overlays (the tweak panel and the HUD).
> The rectangle carries the ray-march shader, which paints the entire chasm
> onto it every frame, so moving the camera is all it takes to explore. There
> are no meshes for the world itself; the only real mesh is a small orange
> cube used to check that the painted image and ordinary geometry overlap
> correctly.

## What is in the scene

[main.tscn](../../scenes/main.tscn) is the main scene, set as
`run/main_scene` in [project.godot](../../project.godot). Its nodes, top to
bottom:

| Node | Type | Role |
| --- | --- | --- |
| `Main` | `Node3D` | Root. |
| `Camera` | `Camera3D` with the free-fly script | The viewpoint; starts at `(20, 0, -30)`. |
| `Camera/RaymarchQuad` | `MeshInstance3D` | A 2 x 2 quad with the ray-march `ShaderMaterial`, parented to the camera. |
| `SeedUniform` | `Node` | Copies the world seed into the quad's shader (see [[tweak-ui]]). |
| `WorldEnvironment` | `WorldEnvironment` | Near-black background and a faint blue-grey ambient light. |
| `DepthTestCube` | `MeshInstance3D` | A 4 m unshaded orange box at `(31, -4, -21)`. |
| `TweakPanel` | instance of the tweak panel scene | Parameter panel (see [[tweak-ui]]). |
| `Hud` | instance of the HUD scene | Frame time, pose and seed overlay (see [[tweak-ui]]). |

### The quad parented to the camera

The ray marcher needs one fragment per screen pixel, and the simplest way to
get that in a 3D scene is a quad that always covers the screen. The quad is a
child of the camera, one unit in front of it, so it moves and turns with the
camera and never leaves the view. Its vertex shader ignores the quad's real
position anyway and pins the four corners to the corners of the screen (see
[[raymarch-shader]]). `extra_cull_margin` is large and shadows are off, so
Godot never culls the quad or lets it cast shadows.

The fragment shader writes a depth value for every pixel it hits. That is
what `DepthTestCube` is for: an ordinary mesh placed among the facades should
be hidden by nearer ray-marched walls and hide farther ones. If the cube is
drawn on top of everything or not at all, the depth output is broken.

### WorldEnvironment

The environment has a solid, almost black background
(`Color(0.02, 0.02, 0.03)`) and a dim ambient colour. The ray-march shader is
unshaded and does its own lighting and fog, so the environment mostly affects
the test cube and the space behind the quad.

### Rendering settings

[project.godot](../../project.godot) renders the 3D view at half resolution
(`scaling_3d/scale=0.5`) and upscales it. The ray marcher is expensive per
pixel, and this keeps the frame rate usable. The UI layers are drawn at full
resolution.

## FreeFlyCamera

[free_fly_camera.gd](../../scripts/free_fly_camera.gd) (`class_name
FreeFlyCamera`) mirrors the controls of the HTML prototypes:

| Input | Effect |
| --- | --- |
| Right mouse drag | Look around. |
| Esc | Capture or release the mouse; while captured, plain mouse motion looks around. |
| W / S | Forward / back along the view direction. |
| A / D | Left / right. |
| Q / E | Down / up along world Y. |
| Shift | Fast speed (`fast_speed` instead of `speed`). |
| Mouse wheel | Scale the base speed, between 0.05x and 50x. |

The movement keys do nothing while a UI text field has focus (`UiKeys`, see
[[tweak-ui]]).

The camera stores its orientation as `yaw` and `pitch` in the prototype's
convention, where yaw 0 looks along +Z. A Godot camera looks along -Z, so the
node's rotation adds half a turn. Because of this, the yaw and pitch shown in
the HUD and saved in presets can be pasted into the prototypes and give the
same view. `set_pose()` places the camera in one call; presets use it.
`look_enabled` switches mouse look off while the tweak panel owns the mouse.

## How to run or check it

- `mise run run` starts the scene; `mise run editor` opens it in the editor.
- Fly towards the orange cube and past a facade to see the depth test at work.
- `mise run check` parses the scripts and loads the project headlessly
  ([[ci-and-export]]).

## References

- [[raymarch-shader]]: what the quad draws.
- [[tweak-ui]]: the panel, HUD and seed nodes in this scene.
- [[0005-right-handed-prototype-camera-basis]]: how the prototype camera
  basis was fixed, which this camera matches.
- [[0003-ray-marcher-is-a-throwaway-prototype]]: why the world is a single
  shader on a quad.
- [[sdf-ray-marching]]: the rendering technique.
- [[PLAN_0.0.1]]: the milestone this scene implements.
