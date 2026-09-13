---
tags:
  - process
  - tooling
status: current
---

# Screenshots

> [!summary]
> `mise run shot <scene> <out.png>` renders one frame of a scene to a PNG
> without opening a window: it sets the seed, the camera pose and any tweak
> panel parameter, waits a number of frames and saves the image. Godot needs
> a real renderer to draw pixels, which `--headless` does not have, so the
> task starts Godot inside Xvfb, an invisible X server, and renders with
> OpenGL on the CPU. Use it whenever you need an image; use `--headless` for
> everything else. It is a local tool and not part of CI.

## Why headless Godot cannot take screenshots

`godot --headless` swaps in the *dummy* display server and the *dummy*
renderer. The dummy renderer accepts every drawing call and does nothing:
there is no GPU context, shaders are never compiled and the viewport texture
stays empty. That is exactly right for checks that only look at numbers
(`smoke`, `preset-check`, `skeleton-histogram`), and useless for anything
that needs pixels.

A real renderer needs a display server to create a window and a surface to
draw into. On the maintainer's desktop that means Wayland, and a window that
pops up in the middle of their work. Workers used to write one-off capture
scripts that did exactly that; `shot` replaces them.

## What Xvfb is

Xvfb ("X virtual framebuffer") is an X11 server that keeps its screen in
memory instead of showing it on a monitor. Programs connect to it like to any
X display and create windows, but nothing is ever shown anywhere.

`xvfb-run` is a small wrapper that starts Xvfb on a free display number
(`-a`), sets `DISPLAY` for the command, runs it and stops the server
afterwards. `-s '-screen 0 1280x720x24'` gives the virtual screen a size and a
24-bit colour depth.

Godot on Linux picks Wayland when `WAYLAND_DISPLAY` is set, so the task also
passes `--display-driver x11` to make it use the Xvfb display. On Arch Linux
the package is `xorg-server-xvfb`.

## Which drivers work, and why

Tested on the maintainer's machine (AMD Radeon, Mesa 26.2, Godot 4.7.2):

| Display | Rendering driver | Result |
| --- | --- | --- |
| x11 (Xvfb) | vulkan | Fails: `No DRI3 support detected - required for presentation`, then `None of the devices supports both graphics and present queues`. Godot then silently **falls back to Wayland and opens a window**. |
| x11 (Xvfb) | opengl3 | Works: `OpenGL API 4.6 (Core Profile) Mesa - Compatibility - Using Device: Mesa - llvmpipe`. |

Vulkan needs DRI3 to show frames on an X display, and Xvfb has no DRI3, so
no Vulkan device can present to it. OpenGL through GLX does not need DRI3:
Mesa renders with *llvmpipe*, its software rasteriser on the CPU. The task
therefore uses `--rendering-driver opengl3`, which runs the project with the
Compatibility renderer instead of Forward+.

To make sure a failure can never reach the desktop, the task runs Godot with
`WAYLAND_DISPLAY` unset: if the X11 driver fails, there is no Wayland to fall
back to and Godot exits instead of opening a window.

Consequences:

- Rendering takes CPU time: a 1280×720 shot of the main scene takes about
  30 s (several cores busy), the skeleton viewer about 20 s.
- The image comes from the Compatibility renderer. For the ray-march scene it
  matches the windowed look closely, but when a Forward+-only effect is the
  point of the image, take it with `--window` (Vulkan, Forward+).

## How the shot is set up

The task calls [shot.gd](../../scripts/tools/shot.gd), a script that
`extends SceneTree`, with the arguments after `--`:

1. It loads the scene and turns off `restore_last` on every TweakPanel, so a
   preset saved during an earlier interactive session cannot change the seed,
   pose or parameters.
2. It sets `WorldState.seed` (default 1, the seed of the reference renders)
   before the scene enters the tree.
3. After the first frame, `--pose x,y,z,yaw,pitch` goes to
   `FreeFlyCamera.set_pose` on the scene's camera. Yaw and pitch are in the
   HTML prototype convention, the same numbers the HUD shows.
4. Every `--params name=value` entry is looked up by name in the tweak
   panel's ParamRegistry and set with `set_value`, so shader uniforms and
   script parameters (for example the skeleton viewer's `radius` and the
   `grammar` values) work the same way. The registry type decides how the
   text is read: numbers, `true`/`false`, `x:y` for a Vector2, `#rrggbb` or
   `r:g:b[:a]` for a Color. An unknown name or a bad value stops the run.
5. It waits `--frames` frames (default 40) so shaders compile and the scene
   settles, then grabs the next drawn frame with `Hud.grab_frame`, the same
   code the in-game P screenshot uses. The HUD and tweak panel are hidden for
   that frame unless `--ui` is given.
6. It checks the image has the requested `--resolution` (default 1280×720),
   saves it and prints one line with the path, size, seed, rendering driver
   and display server. Any error prints `shot: <problem>` and exits with
   status 1.

Film grain is hashed from `TIME`, so two shots of the same state are not
byte-identical unless you pass `--params grain_amount=0`.

## Where outputs go

The PNG goes exactly where you point it; a relative path is relative to the
project root. Put shots under `build/shots/`: `build/` is ignored by git, and
the task drops a `.gdignore` into the output folder so Godot does not import
the images into the project. Never commit shots.

## Using it

```sh
# Main scene, seed 1, the scene's own camera pose.
mise run shot scenes/main.tscn build/shots/main.png

# A chosen seed, pose and parameters, smaller image.
mise run shot scenes/main.tscn build/shots/seed42.png --seed 42 \
	--pose 20,0,-30,0.9,-0.28 --params grain_amount=0 --resolution 960x540

# The skeleton viewer with its legend and a smaller region.
mise run shot scenes/skeleton_viewer.tscn build/shots/skeleton.png \
	--params radius=2 --ui
```

From a worker (an agent or script running on the maintainer's machine):
always `mise run shot`, never an ad-hoc capture script and never a plain
`godot` run that opens a window. Everything that does not need pixels runs
with `--headless`. See [[CONVENTIONS#Running Godot]].

In CI: `shot` is local-only and not part of `mise run check`. CI runners have
no GPU; software rendering with llvmpipe would in principle work there, but
it is slow, needs Xvfb and Mesa installed on the runner, and a picture is not
something a check can pass or fail on by itself.

## Troubleshooting

- **`shot: xvfb-run not found, opening a window`**: install Xvfb
  (`sudo pacman -S xorg-server-xvfb`). Until then the task falls back to a
  normal window.
- **Vulkan or Wayland lines in the log, or a window appears**: something
  bypassed the task. Run it through `mise run shot`, which sets the x11 and
  opengl3 drivers and unsets `WAYLAND_DISPLAY`.
- **Black or half-drawn image**: raise `--frames`; the first frames after
  start compile shaders. A camera inside solid geometry also renders black:
  try another `--pose`. If the log does not show the `llvmpipe` line, the
  OpenGL context was not created; check that Mesa is installed.
- **`shot: image is WxH, expected ...`**: the window did not get the
  requested size. Under Xvfb the task sizes the virtual screen to match, so
  this usually happens with `--window`, where a tiling window manager
  (Hyprland) resizes the window. Use the default Xvfb mode, or a floating
  window rule.
- **`mise ERROR unexpected word: -300,...`**: mise reads a value starting
  with `-` as a flag. Join it to its flag with `=`:
  `--pose=-300,260,-300,0.79,-0.48`.
- **`shot: --params: no registry param named ...`**: the name is the uniform
  or script parameter name, not the label; `mise run ui-params` lists the
  main scene's names.

## References

- [shot.gd](../../scripts/tools/shot.gd): the script.
- [mise.toml](../../mise.toml): the `shot` task.
- [hud.gd](../../scripts/ui/hud.gd): `Hud.grab_frame`.
- [[tools-and-tasks]]: every task and tool script.
- [[tweak-ui]]: the ParamRegistry and presets.
- [[camera-and-scene]]: the camera pose convention.
- [[0001-all-automation-through-mise]]: why this is a task.
