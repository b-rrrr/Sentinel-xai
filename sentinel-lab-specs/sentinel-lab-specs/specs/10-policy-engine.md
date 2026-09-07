# Spec 10 — Response / Defense Policy Engine (`policy`)

Read `00-ARCHITECTURE.md` §2 (invariant 1 — deterministic blocking first) and §7 (dashboard → policy trust boundary) before starting.

## Goal

The only module with any mutation rights over cluster/firewall state, and only for a small allowlisted set of response actions, gated on human approval during development.

## Allowed paths

`policy/**`.

## Build

1. Define a small, explicit allowlist of response actions this engine can ever take — e.g., "temporarily add a source IP to a WAF blocklist for N minutes," "flag an event for analyst review." Do not design this as a general-purpose "run arbitrary remediation" system.
2. Every action requires: the triggering `security_event`, a human approval step (a simple "approve" button in `dashboard` that calls this module, or a CLI confirmation during development — either is fine for a lab), and an audit log entry recording who approved it and when.
3. RBAC: this module's ServiceAccount is the only one with any permission to modify the WAF blocklist config or NetworkPolicy objects — and even then, scoped to a narrow, explicitly listed set of resources, never a wildcard.

## Do not

- Do not let the neural classifier's or `fusion`'s output trigger a policy action automatically without the human-approval step, at any point during this project's development. This is a hard invariant from `00-ARCHITECTURE.md`, not a temporary safety-rails-off-later plan.
- Do not implement this as a general command executor (no arbitrary `kubectl` pass-through, no shell-out to arbitrary scripts based on model output).

## Acceptance tests

- [ ] Triggering a response action without the human-approval step present is rejected.
- [ ] An approved action is logged with approver identity, timestamp, and the triggering `event_id`.
- [ ] The policy module's ServiceAccount cannot perform any cluster action outside its explicit allowlist (verify with `kubectl auth can-i` against a few disallowed actions).
