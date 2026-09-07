# Spec 05 — Knowledge Base & Reasoning Engine (`knowledge-base`)

Read `00-ARCHITECTURE.md` §5.2 (the `rule` schema — every rule you author must conform to this exactly) before starting. This module can be built in parallel with `classifier` (Phase 6) — neither depends on the other.

## Goal

A versioned set of MITRE-grounded rules and a pure, side-effect-free engine that evaluates them against a feature vector + a predicted class.

## Allowed paths

`knowledge-base/**`.

## Build

1. Author rules as individual YAML files under `knowledge-base/rules/`, one file per rule, each matching `00-ARCHITECTURE.md` §5.2 exactly (field names, enum values for `attack_type` must match the `predicted_class` enum from §5.1 minus `BENIGN`/`ANOMALY_UNKNOWN`).
2. Cover, at minimum, one rule per attack category in the `predicted_class` enum: `R-SQLI-*`, `R-XSS-*`, `R-PATHTRAV-*`, `R-CMDINJ-*`, `R-BRUTEFORCE-*`. Author more than one rule per category where realistic variants exist (e.g., different SQLi patterns), but every rule must still map to exactly one `attack_type`.
3. Implement the reasoning engine as a pure function:
   ```python
   def evaluate(features: dict, predicted_class: str) -> list[FiredRule]:
       ...
   ```
   It loads all rules whose `attack_type` matches (or is a reasonable candidate given) `predicted_class`, evaluates each rule's `conditions` against `features`, and returns every rule that fully matches, ranked by `severity` then by number of conditions matched (more specific first).
4. `FiredRule` should carry at least: `rule_id`, `mitre_technique`, `mitre_tactic`, `severity`, and the rendered `explanation_template` (with `{feature_name}` placeholders filled in from `features`).
5. Ship this as a small importable library/service, not a standalone deployment with its own ingress — `fusion` calls it in-process or via a lightweight internal call, per `00-ARCHITECTURE.md` §6.

## Do not

- Do not let a rule's `explanation_template` reference a feature not listed in its own `conditions` — if the template needs a feature for context, add it to `conditions` (even as an informational threshold) so the faithfulness verifier (Phase 7) can actually check it.
- Do not add an `attack_type` value that isn't already in the `predicted_class` enum from `00-ARCHITECTURE.md` §5.1. If a genuinely new category is needed, that's an ADR affecting the schema, not a local addition here.
- Do not make this engine stateful or give it side effects (no DB writes, no network calls) — it must be independently unit-testable against fixture feature vectors alone.

## Acceptance tests

- [ ] Every rule file under `knowledge-base/rules/` validates against the §5.2 schema (write a small schema-validation script, run it in CI or manually before marking this phase done).
- [ ] For at least 10 hand-constructed fixture feature vectors (a mix of clear attacks per category and clear benign cases), `evaluate()` returns the expected fired rule(s) — build this as an actual test file, e.g. `knowledge-base/tests/test_fixtures.py`, not a manual one-off check.
- [ ] `evaluate()` given a benign fixture (no rule conditions satisfied) returns an empty list, not a fabricated low-severity match.
- [ ] Calling `evaluate()` twice with identical inputs returns identical output (purity check — no hidden state).
