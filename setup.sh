#!/bin/bash
# ============================================================
# COMPLETE SETUP SCRIPT FOR SENTINEL LAB
# Run this ON ANY node to set up the full project
# ============================================================

set -e

# =========================================================
# Function: Setup system
# =========================================================
setup_system() {
    echo "[SETUP] Configuring system..."
    sudo swapoff -a
    sudo sed -i '/swap/d' /etc/fstab
    sudo modprobe br_netfilter
    echo "br_netfilter" | sudo tee /etc/modules-load.d/k8s.conf
    sudo sysctl --system > /dev/null
    echo "✓ System configured"
}

# =========================================================
# Function: Install K3s Master
# =========================================================
install_k3s_master() {
    echo "[K3S] Installing master control-plane..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

curl -sfL https://get.k3s.io | sh -s - \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 644

echo "Waiting for cluster to be ready..."
sleep 10
kubectl get nodes

echo ""
echo "Getting master token for agent nodes..."
cat /etc/rancher/k3s/server/token
echo ""

echo "Join URL: https://192.168.1.17:6443"
}

# =========================================================
# Function: Install K3s Agent
# =========================================================
install_k3s_agent() {
    echo "[K3S] Installing agent node..."
    MASTER_IP="192.168.1.17"
    
    if [ -z "$1" ]; then
        echo "ERROR: You must provide the K3s master token"
        echo "Usage: $0 <TOKEN>"
        exit 1
    fi
    
    curl -sfL https://get.k3s.io | sh -s - \
      --server https://192.168.1.17:6443 \
      --token $1 \
      --write-kubeconfig-mode 644
    
    echo "✓ Agent node joined cluster"
}

# =========================================================
# Main Menu
# =========================================================
main() {
    echo "=========================================="
    echo "  Sentinel Lab Setup"
    echo "  Choose which node to configure:"
    echo "=========================================="
    echo ""
    echo "1) Master Node (192.168.1.17) - Control-plane + MongoDB"
    echo "2) Agent Node (192.168.1.11) - App workloads"
    echo "3) Laptop Node (rtx-5060) - ML training"
    echo ""
    read -p "Enter choice [1-3]: " choice

    case $choice in
        1)
            echo "Setting up MASTER NODE..."
            setup_system
            install_k3s_master
            echo ""
            echo "Next: Run setup-agent.sh on other nodes"
            ;;
        2)
            echo "Setting up AGENT NODE..."
            setup_system
            echo ""
            echo "Please run setup-agent.sh on the master node to get the token"
            echo "Then run this script with: bash <MASTER_IP> <K3S_TOKEN>"
            ;;
        3)
            echo "  Setting up LAPTOP (ML Training) node..."
            setup_system
            echo ""
            echo "Laptop setup for ML training:"
            echo "  - Install Python 3.11+"
            echo "  - Clone your branch2-ml-training folder"
            echo "  - pip install -r requirements_ml.txt"
            echo "  - Run: python scripts/train_classifier.py --data-source postgres"
            echo ""
            # Install Python dependencies for ML laptop
            ;;
        *)
            echo "Invalid choice."
            exit 1
            ;;
    esac
}

main "$@"