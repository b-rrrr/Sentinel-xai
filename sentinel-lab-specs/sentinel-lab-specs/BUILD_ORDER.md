# Build Order

Read `00-ARCHITECTURE.md` and `AGENT_INSTRUCTIONS.md` before this file, every session. Then find your current phase below and open **only** the one spec file it names.

| Phase | Spec file | Depends on (gate condition) | Produces |
|---|---|---|---|
| 0 | `specs/01-infrastructure.md` (§Phase 0 section) | `inventory/nodes.yaml` filled in with real hardware numbers | Working k3s cluster, namespaces, RBAC |
| 1 | `specs/01-infrastructure.md` (§Phase 1 section) | Phase 0 acceptance tests pass | MetalLB, Traefik, storage classes |
| 2 | `specs/02-data-layer.md` | Phase 1 acceptance tests pass | Event DB deployed, schema migrated, event-api reachable |
| 3 | `specs/03-demo-app.md` | Phase 2 acceptance tests pass | Demo app(s) deployed in isolated namespace, logging contract emitting |
| 4 | `specs/04-telemetry-waf.md` | Phase 3 acceptance tests pass | WAF blocking mode + log shipping to event-api working end to end |
| 5 | `specs/05-knowledge-base.md` | Phase 4 acceptance tests pass | Rule set authored, reasoning engine passing unit tests on fixtures |
| 6 | `specs/06-neural-classifier.md` | Can run in parallel with Phase 5 (independent) | Trained classifier, inference server with `activation_snapshot` wired in |
| 7 | `specs/07-fusion-faithfulness.md` | Phases 5 AND 6 acceptance tests pass | End-to-end pipeline: event → prediction → rule trace → faithfulness verdict → explanation, all written to `security_event` |
| 8 | `specs/08-dashboard.md` | Phase 7 acceptance tests pass | Dashboard showing live events with faithfulness verdict visible |
| 9 | `specs/09-attack-simulator.md` | Phase 4 acceptance tests pass (can run parallel to 5-8) | Labeled attack traffic generator, ground-truth pipeline wired |
| 10 | `specs/10-policy-engine.md` | Phase 7 acceptance tests pass | Human-approval-gated response actions, audit log |
| 11 | `specs/11-evaluation.md` | Phases 7, 9, 10 acceptance tests pass | Full metrics table populated, evaluation write-up |

## Rules for this table

- **Do not start a phase whose gate condition is not met.** "Looks mostly done" is not a gate condition — the named acceptance tests passing is.
- **Phases 5 and 6 run in parallel** (independent modules, different agents/sessions can build them simultaneously) but **both must complete before Phase 7** — fusion needs both the reasoning engine and the trained classifier's inference server.
- **Phase 9 can start as soon as Phase 4 is done** and doesn't need to wait for 5-8 — it only needs the demo app + telemetry pipeline to generate and log traffic against.
- If you finish a phase and the next one's gate condition still isn't met (e.g., a parallel phase isn't done yet), pick the next available parallel phase rather than idling or starting something out of order.
