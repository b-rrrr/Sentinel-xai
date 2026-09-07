# Spec 11 — Evaluation (`eval`)

Read `00-ARCHITECTURE.md` §5.1 before starting — every metric here is computed from `security_events` rows, using the schema exactly as defined.

## Goal

Populate `GET /api/v1/metrics` with real numbers and produce the project's final written evaluation.

## Allowed paths

`eval/**`. May modify `data-layer/**` only to implement the actual metrics computation behind the already-existing `GET /api/v1/metrics` endpoint (the endpoint shape must not change — only its implementation, which was a stub until now).

## Build

1. Compute, from `security_events` where `ground_truth_label IS NOT NULL` (i.e., attack-sim-generated lab traffic) and separately from the offline classifier test split (Phase 6's held-out set):
   - Accuracy / precision / recall / F1 per `predicted_class`, plus macro-average.
   - False-positive rate (benign flows incorrectly classified as an attack class).
   - Rule validity/coverage: % of true-attack events with at least one fired rule; % of rules in `knowledge-base` that have fired at least once across all evaluated traffic (dead-rule detection).
   - Faithfulness rate: % of fired-rule explanations with `faithfulness_verdict = verified`.
   - Shortcut robustness: faithfulness rate on the Phase 7 adversarial test set vs. the clean test set (the adversarial set's rate should be measurably lower — if it isn't, that's a finding to report, not a bug to hide).
2. Wire these into `GET /api/v1/metrics`'s previously-stubbed implementation.
3. Write `docs/architecture/evaluation-results.md`: the full metrics table (lab traffic and offline dataset side by side), a short discussion of dataset limitations (single dataset family, synthetic lab traffic vs. real-world), and any cases where the faithfulness verifier flagged an explanation as unverified — treat these as findings, not failures to bury.

## Do not

- Do not report a metric you haven't actually computed from real event rows — every number in the final write-up must be traceable to a query against `security_events` or the classifier's saved evaluation JSON.
- Do not adjust the faithfulness threshold at this stage to make the faithfulness-rate number look better — if the rate is lower than hoped, that's the honest result and belongs in the write-up's limitations section.

## Acceptance tests

- [ ] `GET /api/v1/metrics` returns non-null, non-placeholder values for every field.
- [ ] `docs/architecture/evaluation-results.md` exists with the full metrics table and a limitations discussion.
- [ ] Every number in that document can be reproduced by re-running the query/script that generated it (the script itself lives in `eval/` and is checked in, not a one-off notebook cell that was discarded).
