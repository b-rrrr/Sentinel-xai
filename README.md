# Branch 1: Target Website with Backend (MongoDB Placeholder)

## Overview
This branch sets up the sample target website (OWASP Juice Shop) deployed in a homeserver k3s cluster, with MongoDB placeholder connection for the backend. All attacks are automatically stored to the database via the telemetry/WAF pipeline.

## Architecture
- **demo-app**: OWASP Juice Shop running in `demo-app` namespace
- **data-layer**: PostgreSQL database (primary per specs), MongoDB connection string as placeholder
- **telemetry**: ModSecurity WAF + ingest pipeline that normalizes attacks into `security_event` rows
- **attack-sim**: Scripted attack scenarios against Juice Shop
- **dashboard**: Admin overview with "send template" feature

## MongoDB Placeholder
Replace `MONGODB_URI` with the actual URI when the user shares it:
```
MONGODB_URI=mongodb://admin:password@mongo-service.data-layer.svc.cluster.local:27017/sentinel_lab?authSource=admin
```

This placeholder is exported as an environment variable and referenced in deployment configs. The actual DB per specs is PostgreSQL, but MongoDB is included as requested for future use.

## Deployment
```bash
# 1. Deploy Juice Shop
kubectl apply -f k8s/juice-shop.yaml

# 2. Deploy MongoDB placeholder (will be replaced with actual setup)
kubectl apply -f k8s/mongodb-placeholder.yaml

# 3. Deploy WAF + telemetry pipeline
kubectl apply -f k8s/telemetry-waf.yaml

# 4. Deploy event-api and data-layer
kubectl apply -f k8s/data-layer.yaml
```

## Key Components
- `k8s/juice-shop.yaml`: OWASP Juice Shop Deployment + Service + IngressRoute
- `k8s/mongodb-placeholder.yaml`: MongoDB connection config (env vars only, no actual DB)
- `k8s/telemetry-waf.yaml`: ModSecurity WAF + Fluent Bit ingest pipeline
- `k8s/data-layer.yaml`: PostgreSQL + event-api service

## Attack Flow
1. User accesses Juice Shop via `shop.lab.internal`
2. ModSecurity WAF inspects all requests
3. Blocked attacks are logged as structured JSON lines
4. Fluent Bit tail logs and normalizes into `security_event` via `POST /internal/events`
5. Events stored in PostgreSQL (data-layer namespace)
6. Dashboard reads events via `GET /api/v1/events`
7. "Send template" forwards selected events to ML laptop for training