# Writing roles

A role is `roles/<name>.md`: optional front-matter (`sandbox`, `effort`, and a
repeatable `config: key=value`) plus a prompt body that is prepended to the user's
task. This note is how to write a *good* role prompt for Codex / GPT-5.x.

## Principle

Prompt Codex like an operator, not a collaborator. Compact, block-structured prompts
with explicit contracts beat long prose. If output is weak, **tighten the contract —
add a verification or grounding block — rather than asking it to "think harder" or
raising effort.** GPT-5.x follows XML-tagged structure more reliably than prose.

(Distilled from the OpenAI Codex plugin's internal `gpt-5-4-prompting` skill, kept
here so role-writing in this repo doesn't depend on that plugin.)

## Block library

Wrap each in the XML tag shown. Use only the blocks a role actually needs.

| Block | Use it for |
|-------|-----------|
| `<role>` | one line: who Codex is and the stance to take |
| `<task>` | the concrete job and what a good result must cover (nearly always) |
| `<output_contract>` | exact shape, ordering, and brevity of the answer |
| `<operating_stance>` | attitude — e.g. skepticism for review/critique |
| `<grounding_rules>` | don't present inference as fact; label hypotheses; don't invent |
| `<calibration_rules>` | rank by importance; prefer a few strong points; don't pad |
| `<verification_loop>` | verify the answer against the evidence before finalizing |
| `<completeness_contract>` | don't stop at the first plausible answer |
| `<action_safety>` | (writable roles) tight scope, no unrelated refactors, flag irreversible actions |
| `<missing_context_gating>` | don't guess; retrieve the fact or state what's unknown |
| `<research_mode>` | separate observed facts, inferences, and open questions |
| `<citation_rules>` | cite sources; prefer primary/official ones |
| `<dig_deeper_nudge>` | after the first issue, look for second-order failures |
| `<final_check>` | a self-review pass before finalizing |

## Which blocks for which kind of role

- **Read-only analysis** (review, diagnose, critique): `grounding_rules` + `calibration_rules` + an `output_contract`. Add `dig_deeper_nudge` for review, `operating_stance` for critique.
- **Writable** (implement): `action_safety` + `completeness_contract` + `verification_loop`.
- **Research**: `research_mode` + `citation_rules`, plus `config: tools.web_search=true`.
- **Debugging** (diagnose): `missing_context_gating` + `verification_loop`.

## Assembly checklist

1. State the exact job and stance in `<role>` + `<task>`.
2. Pick the smallest `output_contract` that makes the answer easy to use.
3. Add grounding / verification / safety blocks **only where the task needs them**.
4. Set front-matter defaults (`sandbox`, `effort`, `config`) — remember explicit flags override them.
5. Delete redundant instructions before saving.

## Anti-patterns

- Vague framing ("take a look") → a concrete `<task>`.
- No output contract ("report back") → add `<output_contract>`.
- "Think harder / be thorough" → add `<verification_loop>` instead.
- Forcing false certainty ("tell me exactly why it failed") → add `<grounding_rules>`.
- One role doing several unrelated jobs → split into separate roles.

## Worked example: `critique`

`<role>` (independent second opinion; make the thinking better, don't just agree)
→ `<task>` (restate the proposal, then assess) → `<operating_stance>` (constructive
skepticism, no flattery) → `<decision_attack_surface>` (assumptions, reversibility,
cost-if-wrong, scale, second-order effects, the dismissed alternative) →
`<grounding_rules>` → `<calibration_rules>` (rank, don't pad) → `<output_contract>`
(steelman both options, bottom line + confidence + what would change its mind) →
`<final_check>`. Front-matter: `read-only`, `xhigh`, `config: tools.web_search=true`.

> Note on web search: enabling `tools.web_search=true` requires a non-minimal
> `effort` — Codex rejects `web_search` with `effort=minimal`.
