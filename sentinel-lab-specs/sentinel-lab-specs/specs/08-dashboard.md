# Spec 08 — XAI / SOC Dashboard (`dashboard`)

Read `00-ARCHITECTURE.md` §6 (this module only ever calls `data-layer`'s `GET` endpoints — never `POST`/`PATCH`) before starting.

## Goal

A small React frontend + thin API layer showing live security events and, on click, the full explanation with its faithfulness verdict clearly visible — not buried in a tooltip.

## Allowed paths

`dashboard/**`.

## Build

1. Frontend: React app with two views.
   - **Overview:** counts for today by `action_taken` (`GET /api/v1/stats/today`), and a scrollable recent-events list (`GET /api/v1/events?limit=&type=&since=`) showing predicted class + action badge per row.
   - **Event detail (on click):** full row from `GET /api/v1/events/{id}` — render explicitly: `explanation_text`, `faithfulness_verdict` (as a visible badge, e.g. green "Verified" / amber "Unverified — not rule-confirmed"), `mitre_technique`/`mitre_tactic`, `fired_rule_ids`, and a simple bar chart of the top attributed features if available.
2. If `faithfulness_verdict = unverified`, the UI must visually distinguish this event from a verified one at both the list level (a badge/icon) and the detail level (a clear banner, not just a text label) — this is a functional requirement, not a styling nice-to-have, since it's the whole point of the faithfulness mechanism.
3. Use a small charting library (recharts or chart.js) only for the attribution bar chart and, once `eval` (Phase 11) populates real numbers, a faithfulness-rate trend chart against `GET /api/v1/metrics`.
4. Poll `GET /api/v1/events` on an interval (a few seconds) for "live" updates — a websocket/SSE upgrade is a reasonable later ADR, not required for v1.

## Do not

- Do not call `data-layer`'s internal `POST`/`PATCH` endpoints from this module under any circumstance — dashboard is read-only by architecture.
- Do not fabricate placeholder numbers in the metrics view if `GET /api/v1/metrics` returns nulls/zeros before `eval` (Phase 11) is done — show an explicit "not yet computed" state instead of inventing plausible-looking numbers.
- Do not let a missing/null `faithfulness_score` render as if it were a low score — render it as a distinct "not applicable" state (e.g., for `BENIGN` events where faithfulness doesn't apply).

## Acceptance tests

- [ ] Loading the overview page shows today's counts and at least the most recent 20 events, matching what's actually in `data-layer`.
- [ ] Clicking an event with `faithfulness_verdict = unverified` shows a visually distinct state from one with `verified`, confirmed by a human looking at both side by side.
- [ ] The dashboard functions correctly (shows an empty/not-yet-computed state, does not crash) when `GET /api/v1/metrics` returns all nulls, i.e. before Phase 11 is done.
