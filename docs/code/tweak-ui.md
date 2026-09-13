---
tags:
  - code-map
  - ui
status: current
---

# Tweak UI

> [!summary]
> While the program runs, a side panel lets you change every number that
> shapes the chasm and see the result immediately. The panel is not
> maintained by hand: it asks the shader which settings it has and builds a
> slider or picker for each. The same panel sets the world seed and saves
> named presets (all settings, the seed and the camera position) so a view
> can be restored exactly. A small overlay in the corner shows the frame rate,
> camera position and seed, and takes screenshots without itself in the
> picture.

## Keys

| Key | Effect | Handled in |
| --- | --- | --- |
| Tab | Open or close the panel. While open, the mouse is free and camera look is off. | tweak panel |
| H (or F1) | Show or hide the HUD overlay. While hidden, a dimmed "H: HUD   Tab: panel" hint stays in the corner. | HUD |
| P (or F12) | Save a screenshot without the HUD and panel. | HUD |
| R | Pick a random seed. | seed control |
| Esc | Capture or release the mouse for looking around. | camera ([[camera-and-scene]]) |
| WASD, Q/E, Shift, wheel | Fly the camera. | camera ([[camera-and-scene]]) |

H, P, F1, F12 and R are ignored while a text field has focus or with Ctrl,
Alt or Meta held, and the movement keys are ignored while a text field has
focus, so typing a seed or preset name does nothing else. Every action has a
letter key, so keyboards without an F row reach all of them.

## Parts

### World seed

[world_state.gd](../../scripts/world_state.gd) (`class_name WorldState`)
holds the one world seed, an unsigned 32-bit number, default 1. Setting it
clamps the value and emits `seed_changed` only when it actually changes;
`randomize_seed()` picks a random one. It uses static members instead of an
autoload so it also works in the headless `--check-only` and `--script` runs.

[seed_uniform.gd](../../scripts/seed_uniform.gd) (`class_name SeedUniform`)
is a node in the main scene that listens to `seed_changed` and writes the
seed into the ray-march material's `seed` uniform, which the shader's hash
reads ([[hash]]).

### Parameter registry

[param_registry.gd](../../scripts/ui/param_registry.gd) (`class_name
ParamRegistry`) discovers the shader's uniforms at runtime from
`Shader.get_shader_uniform_list()`. It groups them by their
`group_uniforms` block, takes ranges from `hint_range` (or a span around the
default when there is none), and finds defaults from the material, the
rendering server or, when running headless, the uniform's initializer in the
shader source, following `#include` lines. It supports float, int, bool,
vec2 and colour uniforms; other types (such as `vec3`) are skipped, and the
`seed` uniform is left to the seed control. It also reads, writes and resets
values on the material.

### Panel

[tweak_panel.tscn](../../scenes/ui/tweak_panel.tscn) is just a `CanvasLayer`
with [tweak_panel.gd](../../scripts/ui/tweak_panel.gd) (`class_name
TweakPanel`), which builds everything in code: a scrollable 480 px panel on
the right with, from top to bottom, the presets section, the seed control and
one collapsible section per registry group with a Reset button. Floats and
ints get a slider sharing its value with a spin box, bools a check box, vec2s
two spin boxes, colours a colour picker. Every change goes straight to the
material. On start it restores the last used preset.

[seed_control.gd](../../scripts/ui/seed_control.gd) (`class_name
SeedControl`) is the seed row: a text field, a Random button and a Copy
button. Text that is not a non-negative integer reverts to the current seed;
numbers above the 32-bit range clamp.

[ui_keys.gd](../../scripts/ui/ui_keys.gd) (`class_name UiKeys`) holds the
rule every single-key shortcut follows: a fresh press without Ctrl, Alt or
Meta, ignored while a text field (a `LineEdit`, including a spin box's, or a
`TextEdit`) has focus.

### Presets

[preset_store.gd](../../scripts/ui/preset_store.gd) (`class_name
PresetStore`) saves and loads presets as JSON files in `user://presets/`, one
file per preset plus `last.json` naming the last one used. A preset holds
every registry parameter, the seed and the camera position, yaw and pitch.
Floats are written as their shortest exact decimal and read back with an
exact search, so a reloaded preset matches bit for bit. The built-in,
read-only "Prototype defaults" preset is made from the registry defaults,
seed 1 and the scene's starting camera pose. Parameters missing from a file
fall back to their defaults.

### HUD

[hud.tscn](../../scenes/ui/hud.tscn) is a `CanvasLayer` with one monospace
label on a translucent backdrop, driven by
[hud.gd](../../scripts/ui/hud.gd) (`class_name Hud`). It shows FPS, frame
time, camera position, yaw and pitch (in the prototype's convention, so they
can be pasted there), the seed and a one-line summary of the controls. It is
shown on start; hidden, it leaves only a small dimmed hint naming H and Tab.
A screenshot hides the HUD and the layers
listed in `hidden_during_capture` (the tweak panel, in the main scene) for one
frame, and saves it at window resolution to
`user://screenshots/<seed>_<yyyymmdd-hhmmss>.png` and emits
`screenshot_saved`.

## How to run or check it

- `mise run run`, then Tab, H, P and R as above. `user://` is Godot's
  per-user data folder, on Linux `~/.local/share/godot/app_userdata/megastructure/`.
- `mise run ui-params` prints what the registry discovers (headless).
- `mise run preset-check` saves, reloads and compares a preset bit for bit
  (headless); `mise run seed-check` and `mise run screenshot-check` test the
  seed control and screenshots in a window. See [[tools-and-tasks]].

## References

- [[camera-and-scene]]: where the panel, HUD and seed node sit in the scene.
- [[raymarch-shader]]: the uniforms the panel exposes.
- [[hash]]: what the seed feeds.
- [[PLAN_0.0.1]]: the tweak UI epic of milestone 0.0.1.
