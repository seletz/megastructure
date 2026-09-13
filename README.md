# megastructure

![The chasm at seed 1, milestone 0.1.0](docs/images/chasm-0.1.0-seed1.png)

A generative, explorable rendering of a Blame!-style megastructure in Godot 4:
endless strata, vertical shafts, and open chasms between stratified facades.
No gameplay, just a world that generates itself from a seed.

The current milestone (0.1.0) ports the ray-marched chasm prototype into a
fullscreen shader with a free-fly camera and a live tweak panel. See
[`docs/PLAN_0.1.0.md`](docs/PLAN_0.1.0.md).

## Setup

The Godot version and every build task are managed with
[mise](https://mise.jdx.dev/). Install mise, then from the repository root:

```sh
mise install
```

This downloads the pinned Godot build (see `mise.toml`) and the other tools.

To export a build, install the matching export templates once, then export a
preset from `export_presets.cfg`:

```sh
mise run templates
mise run export linux build/linux/megastructure.x86_64
mise run export macos build/macos/megastructure.zip
```

Every [GitHub release](https://github.com/seletz/megastructure/releases) has a
Linux (x86_64) and a macOS (universal) build attached. The macOS build is not
signed or notarized: on first launch, right-click the app and choose Open to
get past Gatekeeper.

## Controls

| Key              | Action                                               |
| ---------------- | ---------------------------------------------------- |
| Tab              | Open or close the tweak panel (frees the mouse)      |
| H (or F1)        | Show or hide the HUD; a small hint stays when hidden |
| P (or F12)       | Save a screenshot without HUD and panel              |
| R                | Pick a random seed                                   |
| Esc              | Capture or release the mouse for looking around      |
| Right mouse drag | Look around                                          |
| W / A / S / D    | Fly forward / left / back / right                    |
| Q / E            | Fly down / up                                        |
| Shift            | Fly fast                                             |
| Mouse wheel      | Scale the flying speed                               |

The single-key shortcuts and the movement keys are ignored while a text field
in the panel has focus. Screenshots land in
`user://screenshots/<seed>_<yyyymmdd-hhmmss>.png`; the absolute path is printed
to the console.

## Tasks

| Task                 | What it does                                             |
| -------------------- | -------------------------------------------------------- |
| `mise run editor`    | Open the project in the Godot editor                     |
| `mise run run`       | Run the project (main scene)                             |
| `mise run check`     | Import, parse all scripts, verify the project loads (CI) |
| `mise run check-scripts` | Parse every `.gd` file and fail on errors            |
| `mise run import`    | Import all assets headlessly (regenerates `.godot/`)     |
| `mise run templates` | Download export templates for the pinned Godot version   |
| `mise run export`    | Export a release build: `mise run export <preset> <out>` |
| `mise run export-debug` | Export a debug build, same arguments                  |
| `mise run clean`     | Remove the import cache and build output                 |
| `mise run hash-vectors` | Print the shared hash reference vectors               |
| `mise run release:release` | Tag and publish the version in `project.godot`, then bump `develop` (`--dry-run` to preview) |
| `mise run release:bump` | Raise the version: `mise run release:bump <patch\|minor\|major>` |
| `mise run release:notes` | Print the changelog section of the next release       |

`mise tasks` lists everything with descriptions.

## Design wiki

`docs/` is a design wiki and opens as an [Obsidian](https://obsidian.md/)
vault: open the `docs/` folder with "Open folder as vault". Start at
[`docs/Home.md`](docs/Home.md), the map of content; how notes are written is in
[`docs/CONVENTIONS.md`](docs/CONVENTIONS.md). The files are plain Markdown and
also read fine on GitHub.
What changed in each version is in [`docs/CHANGELOG.md`](docs/CHANGELOG.md);
how a version is released is in
[`docs/process/releasing.md`](docs/process/releasing.md).

## Documentation

- [`docs/MEGASTRUCTURE_CONCEPT.md`](docs/MEGASTRUCTURE_CONCEPT.md): design
  goals, the three-layer generation architecture, tile vocabulary, look and
  lighting, and the long-term milestones.
- [`docs/PLAN_0.1.0.md`](docs/PLAN_0.1.0.md): the plan for the current
  milestone, with links to the GitHub epics.
- Prototypes: two self-contained ray-marched HTML pages that define the look.
  Open them directly in a browser.
  - [`docs/megastructure.html`](docs/megastructure.html): interior strata,
    shafts and cavities.
  - [`docs/megastructure-chasm.html`](docs/megastructure-chasm.html):
    exterior chasm between facades, the reference for milestone 0.1.0.
- [`docs/hash_vectors.md`](docs/hash_vectors.md): the shared integer hash
  used by the shader, GDScript and the prototypes, with reference vectors.

## Contributing

Branching, commit and pull request rules are in
[`CONTRIBUTING.md`](CONTRIBUTING.md).

## Editing

GDScript files use tabs. A Zed configuration for the Godot language server is
included under `.zed/`.

- [`docs/RESEARCH_WFC.md`](docs/RESEARCH_WFC.md): research for milestone 0.2.0,
  the WFC / model synthesis sector fill in Godot, with a proposed issue
  breakdown.
