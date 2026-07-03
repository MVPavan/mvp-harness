# Report Set

Use this reference when writing the final report files for `codebase-architecture-research`.

## Agent Markdown Reports

`agent/00-index.md`

- Target path, commit or submodule pointer when available, and analysis date.
- One-paragraph system purpose.
- Reading map: which reports exist and what each answers.
- Core architecture in 8-12 bullets.
- Top "read next" source files with why they matter.
- Explicit exclusions and scope limits.

`agent/01-core-architecture.md`

- Main architectural thesis.
- Core modules/packages and responsibilities.
- Ownership boundaries and dependency direction.
- Key abstractions and how they collaborate.
- What is central versus peripheral.

`agent/02-runtime-lifecycle.md`

- Main entry points.
- Startup/config/load sequence.
- Primary request/job/task/session lifecycle.
- Shutdown, cleanup, cancellation, retries, or recovery if present.
- Sequence-style bullet traces grounded in source files.

`agent/03-data-state-and-persistence.md`

- Durable state, local state, caches, generated artifacts, and config.
- Data models and identity schemes.
- Read/write paths.
- Migration/sync/versioning assumptions.
- Consistency, concurrency, and failure-mode notes.

`agent/04-integration-and-extension-points.md`

- CLI/API/protocol surfaces.
- Plugin, hook, skill, agent, provider, or adapter extension mechanisms.
- External services and subprocess boundaries.
- Environment variables and config that materially change behavior.
- Compatibility or contract risks.

`agent/05-operational-model.md`

- How to build, run, test, and inspect the system when relevant.
- Logs, diagnostics, storage locations, and debug surfaces.
- Important commands with caveats.
- What not to run or modify from the parent orchestrators repo.

`agent/90-open-questions.md`

- Unknowns that remain after source reading.
- Claims that are inference rather than confirmed facts.
- Suggested follow-up reads or experiments.
- Architectural risks or drift points.

## HTML Review Report

`html/index.html` should be a self-contained review document derived from the Markdown reports.

Recommended sections:

- Header: codebase name, target path, analysis date, source commit if known.
- Executive architecture summary.
- Core architecture map.
- Runtime lifecycle.
- State and persistence.
- Integration points.
- Operational notes.
- Risks and open questions.
- Canonical Markdown report links.

Keep the HTML factual and dense. Do not turn it into a landing page, marketing page, or decorative dashboard.
