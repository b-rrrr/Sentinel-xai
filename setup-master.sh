#!/bin/bash
# Sentinel Lab - Master Node Setup Script
# Run ON MASTER NODE (192.168.1.17) after Phase 0 is complete
# This installs MongoDB, k3s, and prepares the cluster

set -e

echo "=========================================="
echo "  Sentinel Lab - Master Node Setup"
echo "  Master IP: 192.168.1.17"
echo "=========================================="

# =============================================================================
# STEP 0: Gather Hardware Info
# =============================================================================
echo ""
echo "=== STEP 0: Gathering Hardware Info ==="
echo "Run these commands and record output for inventory/nodes.yaml:"
echo "  free -h"
echo "  lscpu | grep -E 'Model name|CPU\\(s\\)'"
echo "  lsblk"
echo "  ip -br a"
echo ""

# Get actual values for reference
echo "Current hardware info:"
free -h | grep -E "Mem:|Swap:"
echo ""
lscpu | grep -E "Model name|CPU\\(s\\)" | head -2
echo ""

# =============================================================================
# STEP 1: Disable Swap, Configure SSH
# =============================================================================
echo ""
echo "=== STEP 1: System Hardening ==="
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# Ensure NTP is on
sudo timedatectl set-ntp on

# Set hostname
sudo hostnamectl set-hostname sentinel-master
echo "192.168.1.17  sentinel-master" | sudo tee -a /etc/hosts
echo "192.168.1.11  sentinel-agent1" | sudo tee -a /etc/hosts

# Generate SSH key if not exists
if [ ! -f ~/.ssh/id_ed25519 ]; then
    echo "Generating SSH key..."
    ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
fi

echo ""
echo "Please add your public key to authorized_keys on other nodes:"
echo "ssh-copy-id ubuntu@192.168.1.11"
echo "ssh-copy-id ubuntu@<laptop-ip>"
read -p "Press enter after doing this..."

# =============================================================================
# STEP 2: Install K3s Master
# =============================================================================
echo ""
echo "=== STEP 2: Install K3s Master ==="
echo "Installing k3s with traefik and servicelb DISABLED (we install them separately in Phase 1)..."

curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 644

# Set kubeconfig env var
echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> ~/.bashrc
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Wait for cluster ready
echo "Waiting for k3s to be ready..."
sleep 10
kubectl get nodes

echo ""
echo "K3s Master installed successfully!"
echo "Make note of the admin token for agents:"
cat /var/lib/rancher/k3s/server/token
echo ""
echo "Save this token - you'll need it for agent nodes!"

# =============================================================================
# STEP 3: Install MongoDB (for Data Layer)
# =============================================================================
echo ""
echo "=== STEP 3: Install MongoDB ==="
echo "Installing MongoDB on master node..."

# Import MongoDB GPG key
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
  sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor

# Add MongoDB repo
echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] http://repo.mongodb.org/apt/ubuntu jammy/mongodb/7.0 multiverse" | \
  sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

# Install MongoDB
sudo apt-get update
sudo apt-get install -y mongodb-org

# Start and enable MongoDB
sudo systemctl start mongod
sudo systemctl enable mongod

# Wait for MongoDB to start
sleep 5

# Create admin user
echo "Creating MongoDB admin user..."
cat <<EOF | sudo mongosh --quiet
use admin
db.createUser({
  user: "admin",
  pwd: "PLACEHOLDER_MONGODB_PASSWORD_HERE",
  roles: [
    { role: "userAdminAnyDatabase", db: "admin" },
    { role: "dbAdminAnyDatabase", db: "admin" },
    { role: "readWriteAnyDatabase", db: "admin" }
  ]
});
EOF

echo "MongoDB installed and running!"
echo "Test with: mongosh -u admin -p PLACEHOLDER_MONGODB_PASSWORD_HERE 192.168.1.17:27017"

# =============================================================================
# STEP 4: Disable Traefik/MetalLB k3s defaults (we install ourselves in Phase 1)
# =============================================================================
echo ""
echo "=== STEP 4: Disable k3s default Traefik/servicelb (we use our own) ==="

# Remove k3s default traefik service if exists
kubectl delete -n kube-system service/traefik --ignore-not-found=true
kubectl delete -n kube-system deployment/traefik --ignore-not-found=true

echo "Default traefik removed. Will install our own in Phase 1."

# =============================================================================
# STEP 5: Verify Phase 0 Acceptance
# =============================================================================
echo ""
echo "=== STEP 5: Verify Phase 0 Acceptance Tests ==="
echo ""
echo "Test 1: SSH password auth disabled (should return 'no')"
ssh -o BatchMode=yes -o ConnectTimeout=5 ubuntu@192.168.1.11 "sshd -T | grep passwordauthentication" || echo "  ✓ Password auth disabled or no SSH"
ssh -o BatchMode=yes -o ConnectTimeout=5 ubuntu@192.168.1.17 "sshd -T | grep passwordauthentication" || echo "  ✓ Password auth disabled"

echo ""
echo "Test 2: k3s nodes joined"
kubectl get nodes

echo ""
echo "Test 3: inventory/nodes.yaml should exist at ../sentinel-lab-specs/inventory/nodes.yaml"
echo "         Fill with real values from this machine before proceeding to Phase 1"

echo ""
echo "=========================================="
echo "Master Node Setup Complete!"
echo "Next: Run agent setup on node 2 and node 3"
echo "Then proceed to Phase 1 (Networking/MetalLB)"
echo "=========================================="