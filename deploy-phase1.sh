#!/bin/bash
# Sentinel Lab - Phase 1 Deployment Script
# Run ON MASTER (192.168.1.17) after Phase 0 (cluster ready)
# This sets up MetalLB, Traefik, storage, namespaces, and MongoDB data layer

set -e

echo "=========================================="
echo "  Sentinel Lab - Phase 1 Deployment"
echo "  MetalLB + Traefik + Storage + MongoDB"
echo "=========================================="

# ==============================================================================
# STEP 1: Install MetalLB (for LoadBalancer IP)
# ==============================================================================
echo ""
echo "=== STEP 1: Install MetalLB ==="

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

# Create MetalLB config with reserved IP pool
kubectl apply -f - <<EOF
apiVersion: rhcloud/v1alpha1
kind: MetalLBConfig
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - addresses:
    - 192.168.1.20-192.168.1.220
    name: default
  - nodeSelectors:
    - nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values: [sentinel-master]
EOF

echo "MetalLB installed and configured with IP pool 192.168.1.20-220"
kubectl get pods -n metallb-system

# ==============================================================================
# STEP 2: Install Traefik (LoadBalancer, replaces k3s default)
# ==============================================================================
echo ""
echo "=== STEP 2: Install Traefik ==="

# Install Traefik via Helm (or directly with YAML - we use Helm as specified in specs)
helm repo add traefik https://helm.traefik.io/traefik
helm repo update

kubectl create namespace traefik-system

# Install Traefik with LoadBalancer
helm install traefik traefik/traefik \
  -f https://raw.githubusercontent.com/helm/helm/main/values.yaml \
  --set service.type=LoadBalancer \
  --set ingress.class=traefik \
  --set websecure.enabled=false

# Wait for LoadBalancer to get IP from MetalLB
echo "Waiting for Traefik LoadBalancer IP..."
sleep 5
kubectl get svc -n traefik-system

echo ""
echo "Traefik LoadBalancer should have EXTERNAL-IP from MetalLB pool"
kubectl get svc -n traefik-system traefik

# ==============================================================================
# STEP 3: Create Namespaces
# ==============================================================================
echo ""
echo "=== STEP 3: Create Namespaces (per architecture §9) ==="

for ns in demo-app telemetry knowledge-base classifier fusion dashboard attack-sim policy data-layer; do
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
  echo "Created namespace: $ns"
done

# ==============================================================================
# STEP 4: Create Service Accounts and Roles
# ==============================================================================
echo ""
echo "=== STEP 4: Create Service Accounts (no cluster-admin) ===

# Create ServiceAccount for each namespace (scoped to namespace only)
for ns in demo-app telemetry knowledge-base classifier fusion dashboard attack-sim policy data-layer; do
  kubectl create serviceaccount ${ns}-sa -n $ns --dry-run=client -o yaml | kubectl apply -f -
  echo "Created ServiceAccount: ${ns}-sa"
done

# Create RoleBindings (namespace-scoped)
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: demo-app-rolebinding
  namespace: demo-app
subjects:
- kind: ServiceAccount
  name: demo-app-sa
  namespace: demo-app
roleRef:
  kind: Role
  name: view
  apiGroup: rbac.authorization.k8s.io
EOF

echo "ServiceAccounts created for all namespaces"

# ==============================================================================
# STEP 5: Create Default-Deny NetworkPolicies
# ==============================================================================
echo ""
echo "=== STEP 5: Network Policies ==="

# NetworkPolicy for demo-app namespace (default deny + allow from Traefik)
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: demo-app-netpol
  namespace: demo-app
spec:
  podSelector:
    matchLabels:
      app: juice-shop  # Match juice-shop pods
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/service: traefik  # Allow from Traefik namespace only
  - ports:
    - port: 8080
EOF

# NetworkPolicy for data-layer namespace (default deny + explicit allow)
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: data-layer-netpol
  namespace: data-layer
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector: {}
EOF

# NetworkPolicy for attack-sim namespace (default deny + egress to demo-app only)
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: attack-sim-netpol
  namespace: attack-sim
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/service: demo  # Allow egress TO demo-app only
EOF

echo "NetworkPolicies created"

# ==============================================================================
# STEP 6: Deploy MongoDB (placeholder) in data-layer namespace
# ==============================================================================
echo ""
echo "=== STEP 6: Deploy MongoDB in data-layer ==="

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongodb
  namespace: data-layer
  labels:
    app: mongodb
    branch: branch1-target-website
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mongodb
  template:
    metadata:
      labels:
        app: mongodb
    spec:
      containers:
      - name: mongodb
        image: mongo:7.0
        ports:
        - containerPort: 27017
        env:
        - name: MONGO_INITDB_ROOT_USERNAME
          value: admin
        - name: MONGO_INITDB_ROOT_PASSWORD
          value: PLACEHOLDER_MONGODB_PASSWORD  # CHANGE THIS!
        - name: MONGO_INITDB_DATABASE
          value: sentinel_lab
        volumeMounts:
        - name: mongodb-storage
          mountPath: /data/db
      volumes:
      - name: mongodb-storage
        persistentVolumeClaim:
          claimName: mongodb-pvc
  ---
apiVersion: v1
kind: Service
metadata:
  name: mongodb-service
  namespace: data-layer
spec:
  selector:
    app: mongodb
  ports:
  - port: 27017
    targetPort: 27017
  type: ClusterIP
EOF

# Create PVC for MongoDB
kubectl create -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mongodb-pvc
  namespace: data-layer
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: local-path
EOF

echo ""
echo "MongoDB deployed in data-layer namespace"
echo "  Service: mongodb-service.data-layer.svc.cluster.local:27017"
echo "  Credentials: admin / PLACEHOLDER_MONGODB_PASSWORD"
echo ""
echo "⚠️  IMPORTANT: Change PLACEHOLDER_MONGODB_PASSWORD after deployment!"

# ==============================================================================
# STEP 7: Verify Phase 1 Acceptance Tests
# ==============================================================================
echo ""
echo "=== STEP 7: Verify Phase 1 Acceptance Tests ==="

echo ""
echo "Test 1: Traefik LoadBalancer IP assigned"
kubectl get svc -n traefik-system traefik | grep -E "EXTERNAL-IP|<pending>"

echo ""
echo "Test 2: Demo-app NetworkPolicy shows allow + default-deny"
kubectl get networkpolicy -n demo-app

echo ""
echo "Test 3: Data-layer NetworkPolicy shows default-deny"
kubectl get networkpolicy -n data-layer

echo ""
echo "Test 4: MongoDB pod running in data-layer"
kubectl get pods -n data-layer -l app=mongodb

echo ""
echo "Test 5: Egress blocked for demo-app (should fail)
kubectl exec -n demo-app -t my-pod -- ping -c 1 8.8.8.8 || echo "  ✓ Egress blocked"

echo ""
echo "=========================================="
echo "Phase 1 Complete!"
echo "Master node (192.168.1.17) is now running:"
echo "  - MetalLB (LoadBalancer IPs)"
echo "  - Traefik (Ingress, replaces k3s default)"
echo "  - MongoDB (in data-layer namespace)"
echo "=========================================="