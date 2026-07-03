---
name: codebase-architecture-research
description: Investigate a provided source codebase or external repository and produce architecture-focused research reports for future agents and human review. Use when asked to understand a codebase such as external/<name> or external/<name>, map its core architecture, runtime lifecycle, data/state model, inner workings, integration points, or create docs/research/codebases/name/ Markdown and HTML reports while avoiding excessive focus on cosmetic UI, release plumbing, generic tooling, or process layers unless they explain core behavior.
---

# Codebase Architecture Research

## Overview

Use this skill to turn an unfamiliar codebase into durable project knowledge. Prefer source-grounded architecture understanding over broad summaries, dependency inventories, or cosmetic walkthroughs.

The canonical output is Markdown for future agents. HTML is a derived, human-facing review artifact when the user asks for it.

## Output Layout

For a target like `external/<name>`, write reports under:

```text
docs/research/codebases/<name>/
├── agent/
│   ├── 00-index.md
│   ├── 01-core-architecture.md
│   ├── 02-runtime-lifecycle.md
│   ├── 03-data-state-and-persistence.md
│   ├── 04-integration-and-extension-points.md
│   ├── 05-operational-model.md
│   └── 90-open-questions.md
└── html/
    └── index.html
```

Use the same layout for other codebases by replacing `<name>` with the codebase slug. If the user asks for a smaller pass, write only `agent/00-index.md` and `html/index.html` with clear scope notes.

Run `scripts/init_report_tree.py <codebase-path>` when useful to create the output directories and print the expected report paths. Read `references/report-set.md` before writing the final report set.

## Investigation Workflow

1. Resolve scope.
   - Identify the target path, codebase slug, and output directory.
   - Treat submodules as external projects. Do not modify the target codebase unless explicitly asked.
   - If the target is ambiguous, ask one concise question before reading widely.

2. Orient from public entry points first.
   - Read `README`, `AGENTS`, docs indexes, command help docs, package manifests, build files, and top-level source layout.
   - Use `rg --files` and targeted `rg -n` searches to identify entry points, domain terms, storage boundaries, CLI commands, workers, APIs, and tests.
   - Avoid spending time on generated files, vendored code, lockfiles, formatting config, or release metadata unless they affect runtime behavior.

3. Map the core system.
   - Identify the central abstractions and ownership boundaries.
   - Trace the main runtime lifecycle from entry point to core execution and shutdown.
   - Trace the dominant data/control flows, including queueing, persistence, scheduling, plugin loading, RPC/API calls, and error handling when present.
   - Map state: durable stores, local files, caches, config, in-memory registries, migrations, and synchronization assumptions.
   - Map integration points: CLIs, SDK APIs, hooks, plugins, protocol surfaces, environment variables, and external services.

4. Separate core from peripheral.
   - Prioritize code that changes behavior, state, orchestration, or extension semantics.
   - De-prioritize visual styling, cosmetic UI layers, packaging polish, CI/release process, example-only code, and docs-only conventions unless they reveal the core architecture.
   - When a peripheral layer is included, explain why it matters architecturally.

5. Ground every important claim.
   - Cite concrete files and line numbers where possible.
   - Mark uncertain interpretations as inference.
   - Keep an explicit open-questions list instead of filling gaps with guesses.
   - Cross-check docs against implementation when both exist.

6. Write reports.
   - Write agent Markdown first. It is the source of truth for future agents.
   - Write HTML after the Markdown, as a concise review surface for humans.
   - Do not put hidden agent-only instructions in HTML.
   - Keep HTML self-contained with inline CSS and no remote assets unless the user explicitly asks otherwise.

7. Verify before reporting completion.
   - Check that expected report files exist.
   - Check links and local file references.
   - Re-read the report for ungrounded claims, stale placeholders, and over-focus on cosmetic/process layers.
   - Run `git status --short` and report touched files.

## Report Standards

The Markdown reports should help a future agent become productive quickly:

- Start with what the system is for and what problem it solves.
- Name the core modules and explain their responsibilities.
- Explain the runtime path in execution order, not just by directory tree.
- Explain where state lives and how it changes.
- Explain extension seams, invariants, and failure modes.
- Include source-backed "where to read next" pointers.
- Include "do not over-index on" notes for misleading but non-core parts of the repo.

The HTML report should help the user review the same understanding quickly:

- use [$html-artifact](.codex/skills/html-artifact/SKILL.md) Use index as only contents page, detailed codebase realted content move it to differenent pages, with detailed diagrams where ever possible, espicially for architectures.
- Present the architecture map, main flows, risks, and open questions.
- Link or visibly reference the Markdown reports as the canonical source.
- Keep it readable and structured; avoid decorative interfaces that obscure the technical content.

## Useful Commands

```bash
rg --files <codebase-path>
rg -n "main\\(|cobra|click|argparse|Command|server|worker|plugin|hook|store|db|queue|scheduler|orchestr" <codebase-path>
python3 .codex/skills/codebase-architecture-research/scripts/init_report_tree.py external/<name>
```
