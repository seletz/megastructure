---
tags:
  - paper
  - wfc
status: current
authors:
  - Adam Newgas (Boris the Brave)
year: 2019
url: https://www.boristhebrave.com/2019/11/28/tessera-3d-tile-level-generation/
pdf: link-only
licence: commercial Unity asset; blog post and documentation carry no licence notice
---

# Tessera

> [!summary]
> Tessera is a paid Unity add-on that builds 3D levels from tiles using WFC,
> made by the author of DeBroglie. The code is not open, but the launch post
> and the documentation explain how it is meant to be used, including an
> "infinite generator" that splits the world into chunks, fills each chunk
> with the ordinary generator as the player approaches, and makes neighbouring
> chunks fit together.

## Citation

Adam Newgas (Boris the Brave). 2019. Tessera: 3D Tile Level Generation. Blog
post, 28 November 2019.
<https://www.boristhebrave.com/2019/11/28/tessera-3d-tile-level-generation/>

- Documentation, Infinite Generator:
  <https://www.boristhebrave.com/docs/tessera/6/articles/infinite.html>
- Unity Asset Store listing:
  <https://assetstore.unity.com/packages/tools/level-design/tessera-procedural-tile-based-generator-155425>

Link only: commercial product; the web pages carry no licence notice.

## Why it matters here

Its infinite generator is a shipped example of chunked, streamed WFC, the
same shape as the project's sector streaming. The documentation notes that
generating chunks in parallel can slightly lower quality, a trade-off the
face-first boundary scheme is designed to avoid. The documentation is useful;
the code cannot be reused.

## Used by

- [[RESEARCH_WFC]], section 6 (reference implementations).
- Related: [[newgas-2018-debroglie]].
