---
name: graph-first
description: Token-cheap navigation, search, and editing of large codebases across sessions. Use when finding where a symbol is defined or used, tracing call paths / impact / blast radius, doing concept or natural-language code search, renaming or editing symbols, applying structural codemods, or enforcing structural lint rules — query the code graph (serena / CBM) or ast-grep BEFORE reading whole files, and stop on bounded evidence.
---

# Graph-first code intelligence

This repo (when the `code-intel` plugin is enabled and indexed) exposes a symbol
graph and structural tools. The whole point is to answer relational questions
**out-of-band** — return symbols, locations, edges, and signatures instead of
reading file bodies. If you query the graph and then read every candidate file
anyway, the token savings collapse. Don't.

## The one rule
For navigation / where-used / impact / concept-search / rename questions: **query
first, stop on bounded evidence.** Read a file body only when the graph cannot
answer (you need the actual implementation logic, not its location or shape).

## Which tool for what

| Question | Use | Not |
|---|---|---|
| Where is X defined? Who calls X? What does X call? | serena (LSP-exact) or CBM `search_graph` / `trace_path` | reading files to grep |
| Resolve a symbol through import aliases / overloads | **serena** (only tool that scopes aliases) | lexical search |
| "Find code that does <concept>" when names don't match | CBM `semantic_query` (local vectors, no API key) | guessing grep terms |
| What does this diff affect? Which tests to run? | CBM `detect_changes` (impact + risk) | manual tracing |
| One-call architecture overview of an unfamiliar repo | CBM `get_architecture` | reading many files |
| Match code by **shape** (`$X == None`, bare `except:`, missing `timeout=`) | **ast-grep** `run -p '<pat>' -l <lang>` | ripgrep (false-positives in strings/comments) |
| Bulk structural rewrite / codemod across the repo | **ast-grep** `run -p '<pat>' -r '<fix>' -l <lang> -U` | read-edit-write loops |
| Enforce an invariant as a CI gate | **ast-grep** `scan -r rule.yml` | ad-hoc review |
| Rename a symbol / replace a method body / safe-delete | **serena** (`rename_symbol`, `replace_symbol_body`) | reading then Edit-ing the whole file |

## Editing crossover
serena edits win on cross-file refactors and full-symbol rewrites (8–12× cheaper
than read-rewrite cycles). For a 1–3 line tweak inside one file you already have
open, the built-in Edit tool is cheaper — use judgment.

## Using CBM: the required `project` arg
Every CBM query tool (`search_graph`, `trace_path`, `index_status`,
`detect_changes`, `semantic_query`, …) **requires a `project` argument** — a
path-slug name, NOT the repo path. Get it once per session from `list_projects`
(the entry whose `root_path` matches this repo) and reuse it:
`cbm.list_projects({})` → find `root_path == <this repo>` → use its `name` as
`project` in every later call. Omitting `project`, or passing the raw path,
returns `project not found or not indexed` even when the repo IS indexed.

## If the graph is empty
CBM answers `project not found or not indexed` until the repo is indexed (or when
the `project` arg is missing/wrong — see above). Run `/code-intel:index-repo` once
per repo. serena activates via LSP on the project path automatically. If a tool is
missing, run `/code-intel:doctor`.

## Honesty
CBM trades a little completeness for ~10× fewer tokens (~83% answer quality vs
~92% for full file-read). When an answer must be exhaustive (security-critical
sweep), say so and fall back to a full read — but make that a deliberate choice,
not the default.
