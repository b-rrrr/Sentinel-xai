# Spec 03 — Demo Application (`demo-app`)

Read `00-ARCHITECTURE.md` §2 (invariant 2: lab isolation) and §7 before starting.

## Goal

Deploy intentionally-vulnerable practice application(s) that generate realistic attack + benign traffic, inside the isolated `demo-app` namespace from Phase 1, with a logging contract that `telemetry` (Phase 4) can consume.

## Allowed paths

`demo-app/**`. You may reference (not modify) `infra/**` NetworkPolicy definitions.

## Build

1. Deploy one application to start — **OWASP Juice Shop** is the recommended default (well-maintained, covers SQLi/XSS/broken-auth/broken-access-control out of the box). Do not stand up all three of Juice Shop/DVWA/WebGoat in Phase 3; add the others only after the Phase 4 telemetry pipeline is proven end-to-end with one app.
2. Deploy as a standard Kubernetes `Deployment` + `Service` in the `demo-app` namespace, fronted by a Traefik `IngressRoute` on an internal-only hostname (e.g., `shop.lab.internal`) — no public DNS, no wildcard cert, self-signed or plain HTTP internally is acceptable for this lab.
3. Logging contract: ensure the app emits structured JSON access logs (most vulnerable-app images support this via env var or a sidecar; if the chosen image only emits plain text access logs, add a small log-shipping sidecar that parses and re-emits as JSON) with **at minimum**: timestamp, source IP, method, path, status code, and (if available) request body size. This is the raw material `telemetry` normalizes into `raw_features` for `security_event`.
4. Tag every response (via a response header or a fixed prefix in the log line) with the pod's own identity so multi-replica setups can be traced back to a specific instance during debugging — not required for correctness, just useful.

## Do not

- Do not write your own vulnerable code from scratch for this phase. Use maintained, purpose-built training targets (Juice Shop/DVWA/WebGoat) rather than inventing new vulnerable endpoints — they're realistic, well-documented, and don't carry unknown/unintended vulnerabilities that maintained projects have already found and characterized.
- Do not give this namespace egress beyond what Phase 1's NetworkPolicy already allows. If the chosen app image tries to phone home or fetch remote assets at runtime, block it or choose a different image — do not open egress to "make the app work."
- Do not expose this app outside the isolated lab network under any circumstance, including "just for a quick test."

## Acceptance tests

- [ ] `curl http://shop.lab.internal` (from inside the lab network only) returns the app's normal response.
- [ ] The app's access logs are structured JSON (or successfully converted to it) and visible via `kubectl logs`.
- [ ] A test request from outside the isolated namespace's allowed ingress path (e.g., directly from another namespace, bypassing Traefik) is blocked by the Phase 1 NetworkPolicy.
- [ ] The app has zero internet egress (retest the Phase 1 egress-block test specifically against this app's pods, not just a generic test pod).
