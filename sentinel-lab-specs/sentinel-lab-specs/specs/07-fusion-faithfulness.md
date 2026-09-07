# Spec 07 — Neuro-Symbolic Fusion & Faithfulness (`fusion`)

Read all of `00-ARCHITECTURE.md` before starting this one — it's the module that ties every other schema/contract together. Do not start until Phases 5 (`knowledge-base`) and 6 (`classifier`) have both passed their acceptance tests.

## Goal

This is the project's actual contribution. Orchestrate: feature vector → classifier prediction → rule engine trace → **faithfulness verification** (does the trace actually reflect what the model computed, or does it just sound plausible?) → explanation text → write the completed `security_event` back to `data-layer`.

## Allowed paths

`fusion/**`.

## Build

1. Orchestrator: for each partial `security_event` row from `data-layer` (poll or subscribe — either is fine for this scale), call `classifier`'s `/predict` with the row's `raw_features` (re-run feature extraction from `classifier`'s pipeline if `raw_features` isn't already in the final feature-vector shape — reconcile this explicitly, don't assume the shapes already match without checking `feature_names.json`).
2. Call `knowledge-base`'s `evaluate(features, predicted_class)` to get the candidate fired rule(s).
3. **Faithfulness verification** (the core new work):
   - Compute a feature-importance attribution from the classifier's `activation_snapshot` + gradients (integrated gradients or a simpler gradient×input approach for v1 — Captum is the recommended library if using PyTorch).
   - Compare the top-k attributed features against the features cited in the fired rule's `conditions`.
   - Compute an overlap score (weighted Jaccard, or rank-correlation if attribution gives an ordering) between 0 and 1.
   - Tune a threshold on a held-out set (start with 0.5, adjust based on the clean-vs-adversarial test set in step 5) above which the verdict is `verified`.
4. If `faithfulness_verdict = unverified`: do not use the rule's `explanation_template` as the primary explanation text. Instead, generate a fallback explanation stating the top attributed features directly, clearly labeled as "not rule-verified" — never present an unverified symbolic story as if it were confirmed.
5. Build a small adversarial/reasoning-shortcut test set: benign flows deliberately containing surface-level attack-like tokens (e.g., SQL keywords in a non-exploitable context) that should trigger a rule match but fail faithfulness verification. Confirm the verifier correctly down-scores these relative to genuine attack flows.
6. Write the completed fields back via `data-layer`'s `PATCH /internal/events/{event_id}`: `predicted_class`, `confidence`, `fired_rule_ids`, `mitre_technique`, `mitre_tactic`, `faithfulness_score`, `faithfulness_verdict`, `explanation_text`.

## Do not

- Do not present a fired rule's explanation as fact when `faithfulness_verdict = unverified`. This is the single most important behavior in the entire system — get it wrong and the project's core claim (verified, auditable explanations) is false.
- Do not let this module directly modify WAF rules, NetworkPolicy, or any Kubernetes object — it only writes to `data-layer` (`00-ARCHITECTURE.md` invariant 1).
- Do not hardcode the faithfulness threshold without documenting how it was chosen (which held-out set, what the resulting precision/recall of the verifier itself looked like) in `fusion/docs/faithfulness-threshold.md`.

## Acceptance tests

- [ ] Given a genuine attack fixture, the pipeline produces `faithfulness_verdict = verified` with a score above threshold, and `explanation_text` matches the rule's rendered template.
- [ ] Given an adversarial/reasoning-shortcut fixture (step 5), the pipeline produces `faithfulness_verdict = unverified`, and `explanation_text` is the fallback attribution-based text, not the rule template.
- [ ] End-to-end: pushing one partial event through `data-layer` results in a fully-populated row (all §5.1 fields present) within a reasonable time bound (define and record the bound, e.g. under 5 seconds for this hardware).
- [ ] The faithfulness score is monotonically related to attribution/rule overlap in at least one constructed test case (i.e., changing the input to reduce feature overlap measurably reduces the score — this catches a verifier that's actually a no-op returning a constant).
