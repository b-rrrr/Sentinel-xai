# 00 — Architecture (Single Source of Truth)

**Status:** stable. Do not edit except via a human-approved ADR (`docs/decisions/`). Every module spec in `specs/` references this file instead of redefining anything in it.

---

## 1. What this system is

A defensive cyber-range: intentionally vulnerable demo application(s) + WAF/telemetry + a neuro-symbolic detector that classifies traffic, explains its classification against a MITRE ATT&CK-grounded rule base, and **verifies that the explanation is actually faithful to the model's internal computation** rather than a plausible-sounding story. It is not an autonomous offensive system, and the neural/symbolic layer never gates live blocking decisions by itself.

## 2. Non-negotiable invariants

These apply to every module, in every phase. A spec file that appears to conflict with one of these is wrong — flag it, don't build it.

1. **Deterministic-blocking-first.** WAF rules, NetworkPolicy, and the symbolic rule engine's hard-coded severity thresholds are what block/allow traffic. The neural classifier and any LLM-based explanation step never directly control firewall, ingress, or Kubernetes state.
2. **Lab isolation.** The vulnerable demo app(s), attack simulator, and any endpoint that intentionally accepts malicious-looking payloads live only inside the isolated namespace/network defined in §7. Nothing in this system is exposed to the public internet at any phase.
3. **No unrestricted credentials for agents.** Any coding agent building this gets a scoped ServiceAccount/RBAC role limited to the namespaces it needs (see `specs/01-infrastructure.md`), never cluster-admin.
4. **One schema per concept.** Every event, rule, and model I/O shape is defined exactly once, in §5–§6 of this file. No module redefines a schema; they import/reference it.
5. **Faithfulness is a first-class output, not a nice-to-have.** Every explanation shipped to the dashboard carries a `faithfulness_verdict`. An unverified explanation is never presented as if it were verified.

## 3. High-level data flow

```
        REQUEST
           │
           ▼
   Ingress + WAF (rules)  ──────────────► BLOCK ─────► security_event (raw)
           │ ALLOW                                            │
           ▼                                                  ▼
     Demo Application                                 Event Ingest / Normalize
           │                                                  │
           ▼                                                  ▼
      App + access logs ───────────────────────────►  Feature Extraction
                                                               │
                                                               ▼
                                                     Neural Classifier
                                                     (prediction + activations)
                                                               │
                                                               ▼
                                                   Symbolic Reasoning Engine
                                                   (rule base, MITRE mapping)
                                                               │
                                                               ▼
                                                    Faithfulness Verifier
                                                   verified ──┴── unverified
                                                       │             │
                                                       ▼             ▼
                                               Explanation Gen   Flag as
                                                       │         "unverified"
                                                       ▼
                                                 Event Database
                                                       │
                                                       ▼
                                              XAI / SOC Dashboard
```

## 4. Module list (canonical names — use these exact names everywhere)

| # | Module (canonical name) | One-line responsibility | Spec file |
|---|---|---|---|
| 1 | `infra` | K3s cluster, networking, storage, namespaces, RBAC | `specs/01-infrastructure.md` |
| 2 | `data-layer` | Event/rule/model-artifact persistence | `specs/02-data-layer.md` |
| 3 | `demo-app` | Intentionally vulnerable practice target(s) | `specs/03-demo-app.md` |
| 4 | `telemetry` | WAF, runtime (Falco), optional NIDS, log shipping, ingest/normalize | `specs/04-telemetry-waf.md` |
| 5 | `knowledge-base` | MITRE-grounded rule definitions + reasoning engine | `specs/05-knowledge-base.md` |
| 6 | `classifier` | Feature engineering + neural detector + inference server | `specs/06-neural-classifier.md` |
| 7 | `fusion` | Neuro-symbolic fusion + faithfulness verification | `specs/07-fusion-faithfulness.md` |
| 8 | `dashboard` | XAI/SOC dashboard + its API | `specs/08-dashboard.md` |
| 9 | `attack-sim` | Scripted attack scenarios + ground-truth labeling | `specs/09-attack-simulator.md` |
| 10 | `policy` | Response/defense policy gating (human-approved actions) | `specs/10-policy-engine.md` |
| 11 | `eval` | Acceptance tests + research evaluation plan | `specs/11-evaluation.md` |

Every module is a **separate deployable unit** (own namespace-scoped service account, own repo folder, own Dockerfile where applicable). No module reaches into another module's database tables directly — cross-module communication goes through the APIs defined in §6.

## 5. Canonical data schemas (defined once — every module imports this, never redefines it)

### 5.1 `security_event` (the central object of the whole system)

```json
{
  "event_id": "uuid",
  "ts": "ISO-8601 timestamp",
  "source_ip": "string (IP)",
  "target_endpoint": "string",
  "http_method": "string",
  "raw_features": { "...": "flat key/value, keys must match feature_names.json (see classifier spec)" },
  "predicted_class": "string, one of: BENIGN | SQL_INJECTION | XSS | PATH_TRAVERSAL | COMMAND_INJECTION | BRUTE_FORCE | ANOMALY_UNKNOWN",
  "confidence": "float 0-1",
  "fired_rule_ids": ["string, e.g. R-SQLI-001"],
  "mitre_technique": "string or null, e.g. T1190",
  "mitre_tactic": "string or null, e.g. TA0001",
  "faithfulness_score": "float 0-1 or null",
  "faithfulness_verdict": "one of: verified | unverified | not_applicable",
  "explanation_text": "string or null",
  "action_taken": "one of: BLOCKED | ALLOWED | MITIGATED | FLAGGED",
  "ground_truth_label": "string or null — populated only for attack-sim-generated traffic"
}
```

Every module that touches an event uses exactly this field set and exactly these enum values. If a module needs a field not listed here, that is an ADR, not a silent addition.

### 5.2 `rule` (knowledge-base entry)

```yaml
rule_id: string        # format R-<CATEGORY>-<3-digit-number>, e.g. R-SQLI-001
name: string
attack_type: string     # must match one of the predicted_class enum values above (minus BENIGN/ANOMALY_UNKNOWN)
mitre_technique: string  # e.g. "T1190"
mitre_tactic: string     # e.g. "TA0001"
conditions:
  - feature: string      # must exist in feature_names.json
    operator: one of [">=", "<=", ">", "<", "==", "in"]
    value: number | string | list
severity: one of [low, medium, high, critical]
explanation_template: string   # may reference {feature_name} placeholders only for features in `conditions`
```

### 5.3 Model I/O contract (`classifier` inference server)

Request:
```json
{ "features": { "...": "flat key/value, keys from feature_names.json" } }
```

Response:
```json
{
  "predicted_class": "string (see 5.1 enum)",
  "confidence": "float 0-1",
  "per_class_probs": { "CLASS_NAME": "float" },
  "activation_snapshot": { "layer_name": "array of floats — required for fusion/faithfulness, do not omit" }
}
```

`activation_snapshot` is mandatory in every response, from the first working version of the inference server onward. It is not an optional field to add later — the faithfulness verifier (`specs/07`) cannot function without it, and retrofitting it after the model/server contract is frozen elsewhere causes cascading rework.

## 6. Internal API surface (who calls whom)

| Caller | Callee | Endpoint | Payload |
|---|---|---|---|
| `telemetry` (ingest) | `data-layer` | `POST /internal/events` | one `security_event` (partial — pre-classification fields only) |
| `fusion` orchestrator | `classifier` | `POST /predict` | Model I/O contract (§5.3) |
| `fusion` orchestrator | `knowledge-base` | `evaluate(features, predicted_class) -> List[FiredRule]` (in-process function call, not network, if same service) |
| `fusion` orchestrator | `data-layer` | `PATCH /internal/events/{event_id}` | completed `security_event` fields (classification through explanation) |
| `dashboard` | `data-layer` | `GET /api/v1/events`, `GET /api/v1/events/{id}`, `GET /api/v1/stats/today`, `GET /api/v1/metrics` | — |
| `attack-sim` | `demo-app` (via ingress) | HTTP requests carrying a `X-Sentinel-Scenario-ID` header | — |
| `attack-sim` | `data-layer` | `PATCH /internal/events/{event_id}/ground-truth` | `ground_truth_label` |

No module calls another module's database directly. If a spec file seems to require that, it's wrong — flag it.

## 7. Trust boundaries (unchanged regardless of node count)

| Boundary | Crosses | Required control |
|---|---|---|
| Home LAN → lab | HTTP(S) to demo app | Isolated VLAN/subnet, no WAN exposure, DHCP-reserved static IPs only |
| Ingress/WAF → demo-app | Filtered HTTP | WAF blocking mode, structured JSON block logs |
| demo-app namespace → anywhere else | — | Default-deny NetworkPolicy; egress limited to its own DB pod and the ingress; **no internet egress** |
| telemetry → data-layer | `security_event` (partial) | Schema-validated, authenticated internal service account, idempotent by `event_id` |
| classifier/fusion → policy | prediction + evidence | Never executes cluster/firewall commands directly; policy module is the only thing with any mutation rights, and only on human-approved actions during development |
| dashboard → policy | human-approved response action | RBAC, audit log, allowlisted action types only |

## 8. Hardware inventory (fill in before Phase 0 — do not guess)

Actual hardware: **2× Intel Xeon (250GB HDD each, RAM TBD)** + **1× Dell Pentium laptop (currently Fedora, fully reformattable, specs TBD)**.

Do not hardcode RAM/CPU numbers anywhere in the build — capabilities must come from `inventory/nodes.yaml`, filled in with real numbers from each machine (`free -h`, `lscpu`, `lsblk`) during Phase 0 of `specs/01-infrastructure.md`. Role assignment is by **capability tier**, not by fixed node names:

| Tier | Typical role | Assignment rule |
|---|---|---|
| Tier 1 (most RAM + most disk) | k3s control-plane, data-layer (DB), model training | Assign to whichever real node has the most RAM once measured |
| Tier 2 (mid) | demo-app, telemetry/WAF | Second-most-capable node |
| Tier 3 (least — expect this to be the Pentium laptop) | attack-sim, lightweight log shipping only | Least-capable node; keep workloads here bursty/non-critical, never stateful |

## 9. Canonical repository layout

```
sentinel-lab/
├── infra/            # module 1 — k3s manifests, NetworkPolicies, MetalLB/Traefik config
├── data-layer/        # module 2 — DB schema/migrations, event-api service
├── demo-app/          # module 3
├── telemetry/         # module 4 — WAF config, Falco rules, ingest/normalize service
├── knowledge-base/    # module 5 — rules/*.yaml, reasoning-engine service
├── classifier/        # module 6 — training pipeline, inference server, feature_names.json
├── fusion/            # module 7 — orchestrator, faithfulness verifier
├── dashboard/          # module 8 — frontend + its API
├── attack-sim/         # module 9 — scenario scripts
├── policy/             # module 10 — response policy engine
├── eval/               # module 11 — acceptance + evaluation harness
├── inventory/
│   └── nodes.yaml
└── docs/
    └── decisions/       # ADRs
```

Each module folder is where its spec file's "Allowed paths" restricts work to — never edit another module's folder from within a different module's phase.
