# Spec 04 — Telemetry & WAF (`telemetry`)

Read `00-ARCHITECTURE.md` §5.1 (`security_event` schema — this module produces the *partial* pre-classification version of it) and §6 (you are the only module allowed to call `POST /internal/events`).

## Goal

A deterministic WAF in front of `demo-app`, plus a normalization pipeline that turns WAF/app logs into partial `security_event` rows written to `data-layer`.

## Allowed paths

`telemetry/**`.

## Build

1. Add WAF enforcement in front of `demo-app`'s Traefik route using a ModSecurity/Coraza middleware running the OWASP Core Rule Set, in **blocking** mode. Configure it to log every blocked request as one structured JSON line containing at minimum: timestamp, source IP, target path, HTTP method, matched CRS rule ID(s), and a coarse attack-category guess if the CRS rule tags one (SQLi/XSS/etc. — this is a hint for the ingest normalizer, not the final classification, which is `fusion`'s job later).
2. Build the `ingest` service (in `telemetry` namespace): consumes WAF block logs + `demo-app` access logs (via Fluent Bit/Vector DaemonSet or direct log-file tail — pick one and be consistent), normalizes each into the partial `security_event` shape from `00-ARCHITECTURE.md` §5.1 (only these fields at this stage: `source_ip`, `target_endpoint`, `http_method`, `raw_features`, `action_taken` set to `BLOCKED` for WAF blocks or `ALLOWED` for everything else that reached the app), and calls `POST /internal/events` on `data-layer`.
3. `raw_features` at this stage should include whatever cheap, cheap-to-compute signals are available directly from the log line (e.g., payload length, presence of SQL keywords, special-character ratio, request rate from that source IP in the last N seconds) — the full feature vector used by the classifier is finalized in `classifier`'s feature-extraction step (Phase 6), but having a first-pass version here lets Phase 4's acceptance tests be self-contained without waiting on Phase 6.
4. (Optional, only after core pipeline is proven) Add Falco for container/runtime-level signals, feeding the same ingest pipeline as an additional source.

## Do not

- Do not run the WAF in blocking mode in front of `dashboard` or any internal tooling namespace — only in front of `demo-app`.
- Do not let `ingest` call anything other than `POST /internal/events` on `data-layer` — it never calls `PATCH` (that's `fusion`'s and `attack-sim`'s job respectively).
- Do not attempt full network-flow-level feature extraction (packet captures, Suricata NIDS) in this phase — that's an optional later ADR-gated addition, not part of the Phase 4 baseline.

## Acceptance tests

- [ ] A manually issued request containing an obvious SQLi test string (e.g., against Juice Shop's known-vulnerable login form, from inside the lab only) is blocked by the WAF and produces exactly one structured block-log line.
- [ ] That block-log line results in exactly one new row in `data-layer` via `POST /internal/events`, with `action_taken = 'BLOCKED'` and a non-empty `raw_features`.
- [ ] A normal benign request to the demo app produces exactly one row with `action_taken = 'ALLOWED'`.
- [ ] Re-delivering the same log line twice (simulate a log-shipper retry) does not create a duplicate event row (idempotency, per `data-layer`'s contract).
