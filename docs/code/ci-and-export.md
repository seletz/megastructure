---
tags:
  - code-map
  - tooling
status: current
---

# CI and Export

> [!summary]
> Every pull request and every push to `develop` is checked automatically on
> GitHub: a fresh Linux machine installs the pinned tools and runs the same
> `mise run check` a developer runs locally. `develop` only accepts changes
> whose check has passed on an up-to-date branch. Building a standalone Linux
> program from the project uses one export preset and two tasks: one fetches
> Godot's export templates, the other produces the executable.

## CI workflow

[check.yml](../../.github/workflows/check.yml) defines one job, `check`, on
`ubuntu-latest`. It runs for every pull request and for pushes to `develop`.
A newer run on the same ref cancels the older one.

The steps:

1. Check out the repository.
2. Install the shared libraries the Godot binary needs even when headless
   (X11 cursor, xinerama, xrandr, xinput, GL, fontconfig and ALSA, with a
   fallback for the older ALSA package name).
3. Install mise and the tools from `mise.toml` with `jdx/mise-action`, cached
   between runs.
4. Run `mise run check`: import, parse every script, run the main scene
   headlessly for 60 frames and fail on any script or scene error (`smoke`),
   load the project ([[tools-and-tasks]]). The runner has no GPU, but the
   headless dummy renderer does not compile shaders, so `smoke` needs no
   allow-list for shader messages.

The window-based checks (`seed-check`, `screenshot-check`) are not run in CI,
since the runner has no rendering device. The headless `preset-check` and
`code-map-check` are not part of `check` either; run them locally when they
apply.

## Branch protection

`develop` is protected on GitHub:

- the `check` status must pass before merging, and the branch must be up to
  date with `develop` (strict), which is why branches are rebased before they
  are merged;
- force pushes and deleting the branch are not allowed;
- administrators are not forced through these rules, and linear history is
  not required, so merges keep their merge commits.

## Export

[export_presets.cfg](../../export_presets.cfg) has one preset, `linux`: an
x86_64 Linux build with the `.pck` embedded in the executable, exporting all
resources except `build/*` and `docs/*`, to
`build/linux/megastructure.x86_64` by default.

Exporting needs Godot's export templates for exactly the pinned version:

```sh
mise run templates                                        # once per Godot version
mise run export linux build/linux/megastructure.x86_64    # release build
mise run export-debug linux build/linux/megastructure.x86_64
```

`templates` reads the version from `godot --version`, derives the release tag
(a zero patch level is dropped, so 4.7.0 is `4.7-stable`), downloads the
`.tpz` from the Godot GitHub release and unpacks it into
`~/.local/share/godot/export_templates/<version>`. The output folder `build/`
is ignored by git and removed by `mise run clean`.

## How to run or check it

- `mise run check` locally gives the same result as CI.
- The workflow result is shown as the `check` status on each pull request.
- `mise run templates && mise run export linux build/linux/megastructure.x86_64`,
  then run the produced file.

## References

- [[0001-all-automation-through-mise]]: why CI calls a mise task instead of
  Godot directly.
- [[0002-issue-branch-worktrees-and-merge-commits]]: the branch and merge
  workflow the protection rules support.
- [[tools-and-tasks]]: every task in detail.
