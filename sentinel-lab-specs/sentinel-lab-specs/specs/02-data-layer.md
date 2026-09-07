# Spec 02 — Data Layer (`data-layer`)

Read `00-ARCHITECTURE.md` §5.1 (the `security_event` schema — this is the ONLY schema you implement storage for; do not add fields) and §6 (API surface) before starting.

## Goal

A durable, schema-validated store for `security_event` rows, exposed only through the internal API named in `00-ARCHITECTURE.md` §6 — no other module talks to this database directly.

## Allowed paths

`data-layer/**`. Nothing else.

## Build

1. Deploy PostgreSQL (single instance, `local-path-provisioner`-backed PVC — this is a lab, not a production HA target) in the `data-layer` namespace.
2. Create the schema exactly matching `00-ARCHITECTURE.md` §5.1 — every field, every enum value, nothing extra:
   ```sql
   CREATE TABLE security_events (
       event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
       ts TIMESTAMPTZ NOT NULL DEFAULT now(),
       source_ip INET,
       target_endpoint TEXT,
       http_method TEXT,
       raw_features JSONB NOT NULL DEFAULT '{}',
       predicted_class TEXT CHECK (predicted_class IN
           ('BENIGN','SQL_INJECTION','XSS','PATH_TRAVERSAL','COMMAND_INJECTION','BRUTE_FORCE','ANOMALY_UNKNOWN')),
       confidence DOUBLE PRECISION,
       fired_rule_ids TEXT[] NOT NULL DEFAULT '{}',
       mitre_technique TEXT,
       mitre_tactic TEXT,
       faithfulness_score DOUBLE PRECISION,
       faithfulness_verdict TEXT CHECK (faithfulness_verdict IN ('verified','unverified','not_applicable')),
       explanation_text TEXT,
       action_taken TEXT CHECK (action_taken IN ('BLOCKED','ALLOWED','MITIGATED','FLAGGED')),
       ground_truth_label TEXT
   );
   CREATE INDEX idx_events_ts ON security_events (ts DESC);
   CREATE INDEX idx_events_class ON security_events (predicted_class);
   ```
3. Build the `event-api` service (small FastAPI/Go service — pick one and stay consistent with whatever the rest of the project uses) implementing exactly these endpoints, matching the payloads in `00-ARCHITECTURE.md` §6:
   - `POST /internal/events` — insert a partial event (pre-classification fields only), return `event_id`. Must be idempotent: a retry with the same caller-supplied idempotency key does not create a duplicate row.
   - `PATCH /internal/events/{event_id}` — update classification-through-explanation fields.
   - `PATCH /internal/events/{event_id}/ground-truth` — update `ground_truth_label` only.
   - `GET /api/v1/events?limit=&type=&since=` — paginated list.
   - `GET /api/v1/events/{id}` — full row.
   - `GET /api/v1/stats/today` — counts by `action_taken` for today.
   - `GET /api/v1/metrics` — rolling accuracy/precision/recall/F1/FPR/faithfulness-rate (can return zeros/nulls until `eval` module — Phase 11 — populates real computation; the shape must exist now so `dashboard` can be built against it without waiting).
4. Authenticate internal endpoints with a per-namespace ServiceAccount token check (see `AGENT_INSTRUCTIONS.md` — no wildcard access).

## Do not

- Do not add fields to `security_events` beyond `00-ARCHITECTURE.md` §5.1. If you think you need one, write an ADR.
- Do not let any module other than `telemetry` call `POST /internal/events`, or any module other than `fusion` call the classification `PATCH`, or any module other than `attack-sim` call the ground-truth `PATCH`. Enforce this with the per-namespace auth, not by convention.
- Do not implement the actual metrics computation in this module — that belongs to `eval` (Phase 11). This module only serves the shape.

## Acceptance tests

- [ ] `POST /internal/events` with a valid partial payload returns a UUID; calling it again with the same idempotency key returns the same UUID and does not create a second row.
- [ ] `PATCH /internal/events/{id}` with an invalid `predicted_class` (not in the enum) is rejected with a 4xx, not silently accepted.
- [ ] `GET /api/v1/events/{id}` on a completed event returns every field from §5.1, correctly typed.
- [ ] A request to `POST /internal/events` without a valid `telemetry`-scoped service account token is rejected.
