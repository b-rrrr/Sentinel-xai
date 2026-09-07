#!/bin/bash
# Sentinel Lab - Simple Deployment Script
# Run this ON the MASTER node (192.168.1.17) after k3s is installed

set -e

echo "=========================================="
echo " Sentinel Lab - Deployment"
echo "=========================================="

# Check if we're on master
HOST_IP=$(hostname -I | awk '{print $1}')
if [[ "$HOST_IP" != "192.168.1.17" ]]; then
    echo "WARNING: This script should run on master node (192.168.1.17)"
    echo "Current IP: $HOST_IP"
    exit 1
fi

echo ""
echo "Step 1: Apply Namespaces..."
kubectl create namespace demo-app --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace telemetry --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace data-layer --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Step 2: Apply Network Policies..."
# Default-deny for demo-app
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: demo-app-netpol
  namespace: demo-app
spec:
  podSelector:
    matchLabels:
      app: juice-shop
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/service: traefik-ingress
  - ports:
    - port: 8080
EOF

echo ""
echo "Step 3: Deploy Juice Shop (demo-app)..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: juice-shop
  namespace: demo-app
  labels:
    app: juice-shop
spec:
  replicas: 1
  selector:
    matchLabels:
      app: juice-shop
  template:
    metadata:
      labels:
        app: juice-shop
    spec:
      containers:
      - name: juice-shop
        image: bkimminich/juice-shop:latest
        ports:
        - containerPort: 8080
        env:
        - name: NODE_ENV
          value: "production"
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 30
---
apiVersion: v1
kind: Service
metadata:
  name: juice-shop
  namespace: demo-app
  labels:
    app: juice-shop
spec:
  selector:
    app: juice-shop
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
EOF

echo ""
echo "Step 4: Apply Traefik IngressRoute..."
kubectl apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: juice-shop-ingress
  namespace: demo-app
spec:
  entryPoints:
  - web
  routes:
  - match: Host('shop.lab.internal')
    kind: Rule
    services:
    - name: juice-shop
      port: 80
EOF

echo ""
echo "=========================================="
echo "Basic Demo App Deployed!"
echo "Access at: http://shop.lab.internal"
echo "=========================================="
echo ""
echo "To complete setup, also run:"
echo "  1. deploy-phase1.sh (MetalLB, Traefik, storage)"
echo "  2. deploy-mongodb.sh (MongoDB in data-layer)"
echo "  3. setup-agent.sh (agent node setup)"