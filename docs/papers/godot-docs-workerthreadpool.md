---
tags:
  - paper
  - godot
status: current
authors:
  - Juan Linietsky, Ariel Manzur and the Godot community
year: undated
url: https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html
pdf: link-only
licence: MIT (Godot class reference); a web page, no PDF
---

# Godot Docs: WorkerThreadPool

> [!summary]
> The class reference for `WorkerThreadPool`, Godot's shared set of
> background threads. Instead of creating threads yourself, you hand it a
> function to run, check later whether it has finished, and collect the
> result. One rule matters: every task must eventually be waited for, or its
> resources are never cleaned up.

## Citation

Juan Linietsky, Ariel Manzur and the Godot community. *WorkerThreadPool*.
Godot Engine class reference (stable), accessed 2026-09-13.
<https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html>

Link only: a living web page. The class reference is MIT-licensed.

## Why it matters here

Solving a sector may take up to a few seconds in GDScript, so it cannot run
on the main thread. The plan is one `add_task()` per sector, polled with
`is_task_completed()` from `_process`, and always followed by
`wait_for_task_completion()` ("Every task must be waited for completion ...
so that any allocated resources inside the task can be cleaned up"). Tasks
never wait for other tasks, and produce plain data that the main thread turns
into nodes.

## Used by

- [[RESEARCH_WFC]], section 4 (threads) and issue E3 in section 7.
- Related: [[godot-docs-thread-safe-apis]].
- [[sector-jobs]]: `SectorJobs` adds one task per sector, polls
  `is_task_completed` only for tasks that pushed a result and waits on every id.
