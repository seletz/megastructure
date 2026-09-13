# megastructure

A generative, explorable rendering of a Blame!-style megastructure in Godot 4:
endless strata, vertical shafts, and open chasms between stratified facades.
No gameplay, just a world that generates itself from a seed.

The current milestone (0.0.1) ports the ray-marched chasm prototype into a
fullscreen shader with a free-fly camera and a live tweak panel. See
[`docs/PLAN_0.0.1.md`](docs/PLAN_0.0.1.md).

## Setup

The Godot version and every build task are managed with
[mise](https://mise.jdx.dev/). Install mise, then from the repository root:

```sh
mise install
```

This downloads the pinned Godot build (see `mise.toml`) and the other tools.

## Tasks

| Task                 | What it does                                             |
| -------------------- | -------------------------------------------------------- |
| `mise run editor`    | Open the project in the Godot editor                     |
| `mise run run`       | Run the project (main scene)                             |
| `mise run check`     | Import, parse all scripts, verify the project loads (CI) |
| `mise run check-scripts` | Parse every `.gd` file and fail on errors            |
| `mise run import`    | Import all assets headlessly (regenerates `.godot/`)     |
| `mise run export`    | Export a release build: `mise run export <preset> <out>` |
| `mise run export-debug` | Export a debug build, same arguments                  |
| `mise run clean`     | Remove the import cache and build output                 |
| `mise run hash-vectors` | Print the shared hash reference vectors               |

`mise tasks` lists everything with descriptions.

## Documentation

- [`docs/MEGASTRUCTURE_CONCEPT.md`](docs/MEGASTRUCTURE_CONCEPT.md): design
  goals, the three-layer generation architecture, tile vocabulary, look and
  lighting, and the long-term milestones.
- [`docs/PLAN_0.0.1.md`](docs/PLAN_0.0.1.md): the plan for the current
  milestone, with links to the GitHub epics.
- Prototypes: two self-contained ray-marched HTML pages that define the look.
  Open them directly in a browser.
  - [`docs/megastructure.html`](docs/megastructure.html): interior strata,
    shafts and cavities.
  - [`docs/megastructure-chasm.html`](docs/megastructure-chasm.html):
    exterior chasm between facades, the reference for milestone 0.0.1.
- [`docs/hash_vectors.md`](docs/hash_vectors.md): the shared integer hash
  used by the shader, GDScript and the prototypes, with reference vectors.

## Editing

GDScript files use tabs. A Zed configuration for the Godot language server is
included under `.zed/`.
