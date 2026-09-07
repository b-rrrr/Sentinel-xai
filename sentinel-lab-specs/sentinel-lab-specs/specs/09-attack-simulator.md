# Spec 09 — Attack Simulator (`attack-sim`)

Read `00-ARCHITECTURE.md` §2 (invariant 2 — lab isolation) and §6 (this module's only write path is the ground-truth `PATCH`) before starting. Can start as soon as Phase 4 (`telemetry`) is done; does not need to wait for Phases 5-8.

## Goal

Generate labeled attack + benign traffic against `demo-app`, only inside the isolated lab, so the pipeline has real (not just offline-dataset) ground truth to evaluate against in Phase 11.

## Allowed paths

`attack-sim/**`.

## Build

1. Use established, well-documented security-testing tools rather than hand-rolled exploit payloads: OWASP ZAP for automated scanning, sqlmap for SQL-injection scenarios, and simple scripted HTTP clients for brute-force/credential-stuffing scenarios — all targeted only at `demo-app`'s internal-only hostname.
2. Every simulated request must carry an `X-Sentinel-Scenario-ID` header identifying which scripted scenario generated it, and each scenario is pre-labeled with its expected `ground_truth_label` (matching the `predicted_class` enum from `00-ARCHITECTURE.md` §5.1).
3. After a scenario run, correlate its requests to the resulting `security_event` rows (via timestamp + source IP + `X-Sentinel-Scenario-ID` if the header survives into the logs, or timestamp+IP matching within a tight window otherwise) and call `PATCH /internal/events/{event_id}/ground-truth` with the known label.
4. Run scenarios as scheduled, reviewable batches (a `make attack-run TYPE=sqli` style target), not continuously — this keeps each run's resulting events easy to audit.

## Do not

- Do not run any scenario against anything other than `demo-app`'s internal lab hostname. No exception, including "just to double check something."
- Do not call any `data-layer` endpoint other than the ground-truth `PATCH` — this module never sets `predicted_class`, `faithfulness_verdict`, or any other classification field; that's `fusion`'s job.
- Do not write custom exploit code beyond configuring the named, maintained tools (ZAP/sqlmap) against the lab's own demo app.

## Acceptance tests

- [ ] Running one scenario (e.g., `TYPE=sqli`) against `demo-app` produces a batch of requests all carrying the correct `X-Sentinel-Scenario-ID`.
- [ ] Every request in that batch results in a `security_event` row with a correctly-populated `ground_truth_label` matching the scenario's expected label.
- [ ] A benign-traffic scenario run produces events labeled `ground_truth_label = 'BENIGN'`, not left null.
- [ ] Confirm (by inspecting NetworkPolicy + actual traffic) that no request from this module ever reaches anything outside the `demo-app` namespace.
