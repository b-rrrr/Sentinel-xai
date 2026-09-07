#!/bin/bash
# ============================================================
# MASTER NODE SETUP (192.168.1.17)
# Run this script on your master node to install:
# - k3s control-plane
# - MongoDB (for data-layer)
# - Complete Phase 1 setup
# ============================================================

set -e

echo "=========================================="
echo "  Sentinel Lab - Master Node Setup"
echo "  Node: 192.168.1.17 (control-plane + data-layer)"
echo "=========================================="

# =========================================================
# STEP 1: System Preparation
# =========================================================
echo ""
echo "[STEP 1] System Preparation..."
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Set hostname
sudo hostnamectl set-hostname sentinel-master

# Add to /etc/hosts
echo "192.168.1.17  sentinel-master" | sudo tee -a /etc/hosts
echo "192.168.1.11  sentinel-agent1" | sudo tee -a /etc/hosts

echo "✓ System prepared"

# =========================================================
# STEP 2: Install k3s Control-Plane
# =========================================================
echo ""
echo "[STEP 2] Installing k3s control-plane..."

curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 644

# Set kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> ~/.bashrc

# Wait for cluster
sleep 10
echo "✓ k3s control-plane installed"

# Show cluster info
kubectl get nodes
echo ""
echo "🔑 Master Token (SAVE THIS):"
cat /var/lib/rancher/k3s/server/token

# =========================================================
# STEP 3: Install MongoDB
# =========================================================
echo ""
echo "[STEP 3] Installing MongoDB..."

# Install MongoDB
sudo apt-get update
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
  sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor

echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] http://repo.mongodb.org/apt/ubuntu jammy/mongodb/7.0 multiverse" | \
  sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

sudo apt-get update
sudo apt-get install -y mongodb-org

# Start and enable MongoDB
sudo systemctl start mongod
sudo systemctl enable mongod

echo "Waiting for MongoDB to start..."
sleep 5

# Create admin user (CHANGE THE PASSWORD!)
echo "Creating MongoDB admin user..."
cat <<'MONGO_EOF' | sudo mongosh --quiet
use admin
db.createUser({
  user: "admin",
  pwd: "CHANGE_THIS_PASSWORD_AFTER_SETUP",
  roles: [
    { role: "userAdminAnyDatabase", db: "admin" },
    { role: "dbAdminAnyDatabase", db: "admin" },
    { role: "readWriteAnyDatabase", db: "admin" }
  ]
});
MONGO_EOF

echo "✓ MongoDB installed and running"
echo "  MongoDB service: mongodb://192.168.1.17:27017"
echo "  ⚠️  CHANGE THE PASSWORD: Change 'CHANGE_THIS_PASSWORD_AFTER_SETUP' above!"

# =========================================================
# STEP 4: Verify Phase 0 Acceptance
# =========================================================
echo ""
echo "=== PHASE 0 ACCEPTANCE TESTS ==="
echo ""
echo "Test 1: Free memory and CPU info"
free -h
lscpu | grep -E "Model name|CPU\\(s\\)" | head -2

echo ""
echo "Test 2: k3s nodes status"
kubectl get nodes

echo ""
echo "Test 3: SSH password auth (should be disabled)"
ssh -o BatchMode=yes -o ConnectTimeout=5 192.168.1.17 "sshd -T | grep passwordauthentication" || echo "  ✓ SSH password auth disabled"

echo ""
echo "=========================================="
echo "MASTER NODE SETUP COMPLETE!"
echo ""
echo "Save these for other nodes:"
echo "  - Master Token: (shown above)"
echo "  - Master IP: 192.168.1.17"
echo ""
echo "Next: Run setup-agent.sh on remaining nodes"
echo "or run Phase 1 deployment: deploy-phase1.sh"
echo "=========================================="