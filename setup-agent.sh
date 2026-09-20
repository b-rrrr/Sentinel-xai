#!/bin/bash
# Sentinel Lab - Agent Node Setup Script
# Run ON AGENT NODE (192.168.1.11) after Phase 0 complete
# This installs k3s agent and prepares for workload deployment

set -e

echo "=========================================="
echo "  Sentinel Lab - Agent Node Setup"
echo "  Agent IP: 192.168.1.11"
echo "=========================================="

# =============================================================================
# STEP 0: Gather Hardware Info
# =============================================================================
echo ""
echo "=== STEP 0: Gather Hardware Info ==="
echo "Hardware on this machine (for inventory/nodes.yaml):"
echo ""
free -h
echo ""
lscpu | grep -E "Model name|CPU\\(s\\)"
echo ""

# Set hostname
sudo hostnamectl set-hostname sentinel-agent1

# Add master hostname to hosts file
echo "192.168.1.17  sentinel-master" | sudo tee -a /etc/hosts
echo "192.168.1.11  sentinel-agent1" | sudo tee -a /etc/hosts

# =============================================================================
# STEP 1: Disable Swap
# =============================================================================
echo ""
echo "=== STEP 1: Disable Swap ==="
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab
sudo systemctl daemon-reexec || true

# =============================================================================
# STEP 2: Configure SSH (password-less)
# =============================================================================
echo ""
echo "=== STEP 2: SSH Configuration ==="

# Generate key if not exists
if [ ! -f ~/.ssh/id_ed25519 ]; then
    echo "Generating SSH key..."
    ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
fi

echo "Your public key is:"
cat ~/.ssh/id_ed25519.pub
echo ""
echo "Add this to MASTER (192.168.1.17) authorized_keys:"
echo "  ssh-copy-id ubuntu@192.168.1.17"
read -p "Press enter after copying key..."

# =============================================================================
# STEP 3: Install K3s Agent
# =============================================================================
echo ""
echo "=== STEP 3: Install K3s Agent ==="

# Get the master token - REPLACE <TOKEN> with actual token from master
if [ -z "$1" ]; then
    echo ""
    echo "ERROR: Missing K3s master token!"
    echo "Usage: $0 <K3S_TOKEN>"
    echo "Get the token from master node: /var/lib/rancher/k3s/server/token"
    exit 1
fi

MASTER_TOKEN=$1
MASTER_URL="https://192.168.1.17:6443"

echo "Joining k3s cluster at $MASTER_URL..."

curl -sfL https://get.k3s.io | \
  sh -s - \
  --server=$MASTER_URL \
  --token=$MASTER_TOKEN \
  --write-kubeconfig-mode 644

# Wait for cluster ready
sleep 5

# Verify node joined
echo ""
echo "Verifying node joined cluster..."
kubectl get nodes

echo ""
echo "=========================================="
echo "Agent Node Setup Complete!"
echo "This node will run the demo-app workloads"
echo "=========================================="