---
tags:
  - process
  - moc
status: current
---

# Process

> [!summary]
> How work moves from an idea to a published version: the steps a person
> follows, written down so they are the same every time. Branches, commits
> and pull requests are described in `CONTRIBUTING.md` at the repository root;
> the notes here cover the processes that span more than one pull request.

## Notes

| Process | Note | Covers |
| --- | --- | --- |
| Maintaining | [[maintaining]] | Creating and removing issue worktrees, the state of open pull requests, rebasing, waiting for the check and merging with `wt:new`, `wt:rm`, `pr:status` and `pr:merge`. |
| Screenshots | [[screenshots]] | Rendering a scene to a PNG without a window with `mise run shot`: why headless cannot render, Xvfb and the x11 and opengl3 drivers, seed, pose and params, outputs, CI and troubleshooting. |
| Releasing | [[releasing]] | Versioning, `mise run release:release`, the release workflow, patch and milestone releases, verifying a release. |

## References

- [CONTRIBUTING.md](../../CONTRIBUTING.md): branches, commits, checks, pull
  requests and releases in short.
- [[0001-all-automation-through-mise]]: every step is a mise task.
- [[0014-develop-is-always-the-next-version]]: the rule behind releasing.
