# Branch 3: Admin Overview Dashboard with Send Template

## Overview
React-based XAI/SOC dashboard for the Sentinel Lab system. Displays live security events, model training metrics, and faithfulness verdicts. Features a "Send Template" button to forward events to the ML/DL training laptop (outside the homeserver network).

## Architecture
- **Frontend**: React app with two views (Overview + Event Detail)
- **API Layer**: Thin wrapper calling `data-layer` GET endpoints
- **Backend Integration**: Reads from PostgreSQL via `data-layer` event-api service
- **ML Integration**: Send training data to RTX 5060 laptop inference server

## Key Features
1. **Overview View**: 
   - Today's counts by `action_taken` (BLOCKED, ALLOWED, MITIGATED, FLAGGED)
   - Scrollable recent events list with predicted class + action badge
   - Faithfulness verdict badges (green "Verified" / amber "Unverified")

2. **Event Detail View** (on click):
   - Full row rendering from `GET /api/v1/events/{id}`
   - Explicit: `explanation_text`, `faithfulness_verdict` (visible badge)
   - `mitre_technique`/`mitre_tactic`, `fired_rule_ids`
   - Bar chart of top attributed features (if available)
   - Special handling for `faithfulness_verdict = unverified` (visually distinct)

3. **Send Template Feature**:
   - Button in event detail view to forward event data to ML laptop
   - POSTs to `http://<laptop-ip>:8000/receive-training-data`
   - Includes: `raw_features`, `ground_truth_label`, `predicted_class`, etc.
   - Visually indicates when template has been sent

4. **Metrics Resilience**:
   - Graceful handling when `GET /api/v1/metrics` returns nulls/zeros
   - Shows "not yet computed" state instead of inventing numbers
   - Distinct "not applicable" state for `faithfulness_score` on BENIGN events

## Deployment
```bash
# Install dependencies
npm install

# Start development server
npm start

# Production build
npm run build
```

The dashboard runs as a static frontend served by Traefik in the `dashboard` namespace.
It only makes read calls to `data-layer` namespace - never POST/PATCH (per architecture invariant).

## API Endpoints Used
- `GET /api/v1/events?limit=20&type=all&since=` - Recent events list
- `GET /api/v1/stats/today` - Today's action counts
- `GET /api/v1/events/{id}` - Full event detail
- `GET /api/v1/metrics` - Model metrics (stubbed until Phase 11)
- `POST /send-template` - Forward events to ML laptop (custom endpoint)