---
name: deep-research
description: Use only when the user explicitly invokes `$deep-research`, says "use deep research", or asks to run this specific skill. Produces decision-grade research with scoped depth, source strategy, synthesis, counterarguments, and HTML artifacts for human review. Do not trigger implicitly for ordinary analysis, brainstorming, codebase research, document review, cost estimates, or quick questions.
---

# Deep Research

Use this skill only by explicit request. Its job is to turn an open research question into a source-grounded, decision-useful HTML artifact.

## Core Rules

- Keep scope tight. Ask before expanding materially beyond the user's question.
- Scale depth to decision risk, not curiosity.
- Prefer primary/current sources for unstable, legal, financial, medical, vendor, API, pricing, or standards claims.
- Separate facts, inferences, and open questions when evidence is incomplete.
- Human-facing output is HTML via `$html-artifact`.
- Markdown is only for agent-facing notes, scratch plans, or future-agent handoff when requested.

## Depth Levels

Choose the smallest level that fits the decision.

| Level | Use When | Expected Work |
|---|---|---|
| Focused | Low-risk understanding or option scan | 3-5 strong sources, concise synthesis, clear caveats |
| Standard | Product, tool, market, policy, or architecture choice | 8-15 sources, comparison matrix, tradeoffs, risks, recommendation or decision points |
| Deep | High spend, high-stakes, fast-changing, regulated, investing, or strategic decision | Primary-source sweep, opposing views, failure modes, confidence grading, red-team section |

If the user asks for "thorough", "deep", "source-grounded", "current", or "decision-grade", default to Standard or Deep. If the scope would balloon, pause and ask.

## Workflow

1. **Clarify only what matters.**
   - If the brief is vague, ask up to 3 questions: decision, scope boundary, constraints.
   - If the brief is clear, proceed.

2. **Plan the research.**
   - State the core question.
   - Pick one playbook from `references/playbooks.md`.
   - Pick only the relevant framework sections from `references/frameworks.md`.
   - Read `references/source-selection.md` for source weighting.

3. **Research.**
   - Gather enough sources for the chosen depth.
   - Track source date, retrieval date, authority, and known bias.
   - Prefer primary docs, official filings, research papers, regulator pages, SDK docs, and direct product docs where they exist.
   - Use community/review/forum evidence for implementation reality, not as sole proof of factual claims.

4. **Synthesize.**
   - Read `references/synthesis-engine.md` before writing conclusions.
   - Identify convergence, contradictions, missing evidence, second-order effects, and failure modes.
   - Red-team the emerging recommendation.

5. **Write the artifact.**
   - Use `$html-artifact` for the final human-readable report.
   - Include: TL;DR, scope, method, findings, comparison table or landscape map, counterarguments, decision points, recommendation if asked, sources, confidence, and open questions.
   - If the user requested a repo artifact, save it under the requested repo path. Otherwise follow `$html-artifact` output protocol.

## Reference Routing

Read only what the task needs:

| File | Read When |
|---|---|
| `references/source-selection.md` | Always, before web/source collection |
| `references/playbooks.md` | Always, but only the relevant playbook |
| `references/frameworks.md` | Only selected framework sections |
| `references/synthesis-engine.md` | During synthesis before final writing |
| `references/examples.md` | Only when unsure about quality or format |

## Domain Emphasis

Optimize for technology, investing, product, developer tooling, architecture, and policy research. Healthcare examples are allowed only when the user asks for healthcare.

## Do Not

- Do not use this skill unless explicitly requested.
- Do not turn a small question into a large research project.
- Do not broaden scope without asking.
- Do not produce generic market summaries.
- Do not bury uncertainty.
- Do not present a single narrative when credible opposing evidence exists.
- Do not use Markdown as the final human report unless the user explicitly asks.
