---
tags:
  - meta
status: current
---

# Wiki Conventions

> [!summary]
> The rules for writing and maintaining notes in this wiki. Every note opens
> with a short plain-language summary, then goes into detail, then lists its
> references. Notes link to each other with wikilinks and to source code with
> relative links. Papers are stored in the vault only when their licence
> allows it. When code changes what a note describes, the note changes in the
> same pull request.

## Opening the vault

`docs/` is the vault root: open that folder in Obsidian ("Open folder as
vault"). The committed settings in `docs/.obsidian/` are deliberately
minimal: readable line length, wikilinks, the shortest link format, and
attachments in `papers/pdf`. Workspace state, cache and plugins are ignored
by git. The folder carries a `.gdignore` so the Godot editor never imports it.

The files also read fine on GitHub, where wikilinks show as plain text.

## Note structure

Every note follows the same order:

1. **Front matter** (see below).
2. **Title** as a level-one heading.
3. **Summary**: one paragraph in plain language in a `> [!summary]` callout.
   A reader who stops here should know what the note is about and why it
   matters. No jargon that the note has not explained, no marketing tone.
4. **Details**: the substance, in as many sections as needed.
5. **References**: papers, links and code the note draws on, in a final
   `## References` section.

Headings go no deeper than three levels (`###`). If a note needs more, split
it into several notes and link them.

## Front matter

Each note starts with YAML front matter:

```yaml
---
tags:
  - algorithm
status: current
sources:
  - "[[merrell-2007-model-synthesis]]"
---
```

- `tags`: a short list of lowercase topics (`concept`, `plan`, `research`,
  `algorithm`, `paper`, `decision`, `code-map`, ...). Nested tags such as
  `milestone/0.0.2` are fine.
- `status`: one of
  - `draft`: being written, may be incomplete or wrong;
  - `current`: describes the project as it is;
  - `superseded`: kept for history; the note links to what replaced it.
- `sources`: optional list of the paper notes or URLs the note is based on.

## Naming

- File names are kebab-case: `walkable-graph.md`, `merrell-2007-model-synthesis.md`.
- Titles (the level-one heading) are in Title Case: `# Walkable Graph`.
- Paper notes are named `<first-author>-<year>-<short-title>`.
- The documents that predate the wiki (`MEGASTRUCTURE_CONCEPT.md`,
  `PLAN_0.0.1.md`, `RESEARCH_WFC.md`, `hash_vectors.md`) keep their names so
  existing links from code, issues and pull requests keep working.
  `Home.md` and `CONVENTIONS.md` are named to stand out as entry points.

## Linking

- **Between notes:** wikilinks, `[[walkable-graph]]`, or with a heading,
  `[[PLAN_0.0.1#Decision: shared integer hash]]`. Link only to notes that
  exist; mention planned notes as plain text.
- **To code:** relative markdown links from the note to the file in the
  repository, for example
  [chasm.gdshaderinc](../shaders/include/chasm.gdshaderinc). Name the function
  or uniform in the text if the file is long. Never copy code into a note; it
  goes stale.
- **To papers:** link the paper's note, `[[merrell-2007-model-synthesis]]`,
  not the PDF or the publisher's page. The paper note holds the citation, the
  URL and the PDF.
- **To issues and pull requests:** full GitHub URLs, or `#123` in plain text.

## Papers and licensing

A paper's PDF is downloaded into `papers/pdf/` only when its licence allows
redistribution, for example:

- arXiv preprints;
- author-hosted preprints with a notice permitting redistribution;
- material under MIT, CC BY or a similar open licence.

In every other case (publisher PDFs, paywalled articles, anything without a
clear licence) the note records the full citation and links to the online
resource, and no copy is committed. The paper note states which case applies
and, if the PDF is stored, under which licence.

## Maintaining the wiki with the code

- A pull request that changes behaviour described in a note updates that
  note in the same pull request. A note that no longer matches the code is a
  bug.
- A pull request that settles a design question adds or updates a decision
  note.
- When a note stops being true, set `status: superseded` and link its
  replacement instead of deleting it.
- When a file linked from a note is moved or renamed, fix the relative links.
  A search for the old path under `docs/` finds them.
- New notes are linked from [[Home]] or from a note that is.

## Changelog

- A pull request that changes behaviour, controls, defaults, tooling or
  documentation structure adds one line under `Unreleased` in [[CHANGELOG]],
  in the matching Added, Changed, Fixed or Docs list: one short plain sentence
  ending with the pull request number, for example `(#33)`.
- Newest items come first everywhere: the new line goes at the top of its
  list, and the newest version section sits directly under `Unreleased`.
- A release moves the `Unreleased` entries under a new `<version> - <date>`
  heading and gets a git tag.
