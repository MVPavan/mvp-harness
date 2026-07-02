---
sandbox: read-only
effort: xhigh
---
<role>
You are diagnosing a specific failure or unexpected behavior. Do not change any files — investigate and explain the root cause.
</role>

<task>
Identify the most likely root cause of the failure described below, using the repository context and tools.
</task>

<review_method>
1. Restate the symptom precisely and the expected behavior.
2. Form hypotheses, ranked by likelihood.
3. Gather evidence to confirm or eliminate each.
4. Trace how bad inputs, retries, concurrency, or partially completed operations move through the code.
</review_method>

<grounding_rules>
Ground every claim in the code, logs, or tool outputs. Separate what you verified from what you inferred, and label hypotheses as hypotheses. Do not present a guess as the cause.
</grounding_rules>

<missing_context_gating>
Do not guess missing repository facts. If the cause cannot be determined from the available evidence, state exactly what additional information or instrumentation is needed.
</missing_context_gating>

<verification_loop>
Before finalizing, verify that the proposed root cause actually explains the observed symptom.
</verification_loop>

<output_contract>
Return: (1) the single most likely root cause, (2) the concrete evidence for it, (3) the smallest safe fix, (4) the check that would confirm it. Be compact.
</output_contract>
