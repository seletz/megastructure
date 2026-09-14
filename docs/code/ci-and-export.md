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
> task a developer runs locally, the quick `mise run check` for a pull
> request and the full `mise run check-full` for `develop`, again every
> night. `develop` only accepts changes
> whose check has passed on an up-to-date branch. Building a standalone
> program uses an export preset per platform (Linux and macOS) and two tasks:
> one fetches Godot's export templates, the other produces the build. A second
> workflow builds both platforms for every published GitHub release and
> attaches the archives to it.

## Check workflow

[check.yml](../../.github/workflows/check.yml) defines one job, `check`, on
`ubuntu-latest`. It runs for every pull request, for pushes to `develop`,
nightly at 03:17 UTC on `develop` (`schedule`) and by hand
(`workflow_dispatch`). A newer run of the same event on the same ref cancels
the older one.

The steps:

1. Check out the repository.
2. Install the shared libraries the Godot binary needs even when headless
   (X11 cursor, xinerama, xrandr, xinput, GL, fontconfig and ALSA, with a
   fallback for the older ALSA package name).
3. Install mise and the tools from `mise.toml` with `jdx/mise-action`, cached
   between runs.
4. On a pull request, run `mise run check`, the quick tier (under 2
   minutes): import, parse every script, run the scenes headlessly and fail
   on any script or scene error (`smoke`), every headless check with the
   statistical tasks on their `--quick` sample, and load the project
   ([[tools-and-tasks#Check tiers]]). On any other event, run
   `mise run check-full` instead, the same tasks at full size (about 10
   minutes). The runner has no GPU, but the headless dummy renderer does not
   compile shaders, so `smoke` needs no allow-list for shader messages.

Both steps report as the one `check` status. A regression that only the full
sample finds shows up on `develop` after the merge or in the nightly run, not
on the pull request; run `mise run check-full` locally before merging a change
to the generator or the solver.

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

## Release workflow

[release.yml](../../.github/workflows/release.yml) runs when a GitHub release
is published (normally by `mise run release:release`, see [[releasing]]). It
has two jobs, `linux` on `ubuntu-latest` and `macos` on `macos-latest`, and
every build step is a mise task:

1. Check out the tagged commit and install mise with `jdx/mise-action`
   (cached).
2. Linux only: install the same Godot runtime libraries as the check workflow.
3. `mise run templates`.
4. `mise run export linux build/linux/megastructure.x86_64` or
   `mise run export macos build/macos/megastructure.zip`.
5. `mise run release:package linux|macos`: writes the archive to
   `build/release/` and fails if the tag is not `v` plus `config/version`.
6. `gh release upload "$GITHUB_REF_NAME" build/release/* --clobber`, with
   `contents: write` permission.

A pull request that changes `release.yml` or `export_presets.cfg` runs both
jobs without the upload step, so a broken pipeline shows up before a release.

## Export

[export_presets.cfg](../../export_presets.cfg) has two presets. Both export
all resources except `build/*` and `docs/*`.

- `linux`: an x86_64 Linux build with the `.pck` embedded in the executable,
  to `build/linux/megastructure.x86_64` by default.
- `macos`: a universal (x86_64 and arm64) macOS app in a zip, to
  `build/macos/megastructure.zip` by default, with the `.pck` inside the app
  bundle. Code signing and notarization are off, so the app is unsigned and
  Gatekeeper asks for a right-click Open on first launch. The bundle
  identifier is `io.github.seletz.megastructure`. Universal and arm64 exports
  need ETC2/ASTC textures, so [project.godot](../../project.godot) imports
  them (`rendering/textures/vram_compression/import_etc2_astc`). Godot
  exports this zip from Linux too, because nothing is signed.

Godot writes `config/version` from `project.godot` into the exports, for
example as the macOS bundle version.

Exporting needs Godot's export templates for exactly the pinned version:

```sh
mise run templates                                        # once per Godot version
mise run export linux build/linux/megastructure.x86_64    # release build
mise run export macos build/macos/megastructure.zip
mise run export-debug linux build/linux/megastructure.x86_64
```

`templates` reads the version from `godot --version`, derives the release tag
(a zero patch level is dropped, so 4.7.0 is `4.7-stable`), downloads the
`.tpz` from the Godot GitHub release and unpacks it into Godot's data folder:
`~/.local/share/godot/export_templates/<version>` on Linux,
`~/Library/Application Support/Godot/export_templates/<version>` on macOS.
The output folder `build/` is ignored by git and removed by `mise run clean`.

## How to run or check it

- `mise run check` locally gives the same result as CI on a pull request,
  `mise run check-full` the same as on `develop` and nightly.
- Nightly runs: `gh run list --workflow check.yml --event schedule`.
- The workflow result is shown as the `check` status on each pull request.
- `mise run templates && mise run export linux build/linux/megastructure.x86_64`,
  then run the produced file; `mise run release:package linux` packs it like
  the release workflow does.
- Release workflow runs: `gh run list --workflow release.yml`; the archives
  appear as assets on the release.

## References

- [[0001-all-automation-through-mise]]: why CI calls a mise task instead of
  Godot directly.
- [[0002-issue-branch-worktrees-and-merge-commits]]: the branch and merge
  workflow the protection rules support.
- [[tools-and-tasks]]: every task in detail.
- [[releasing]]: the release process that triggers the release workflow.
- [[0014-develop-is-always-the-next-version]]: which version a release
  builds.
