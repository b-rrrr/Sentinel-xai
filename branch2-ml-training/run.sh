#!/bin/bash
# Launch script for ML/Training Branch (branch2-ml-training)
# Runs on RTX 5060 laptop outside the homeserver network

set -e

echo "=== Sentinel Lab ML Training Template ==="
echo ""

# Check if we're in the right directory
if [ ! -f "requirements_ml.txt" ]; then
    echo "ERROR: requirements_ml.txt not found. Are you in the branch2-ml-training directory?"
    exit 1
fi

# Install dependencies
echo "Installing dependencies..."
pip install -r requirements_ml.txt 2>&1 | tail -5

echo ""
echo "=== Initialization Complete ==="
echo ""
echo "Available commands:"
echo "  1. Train model:      python scripts/train_classifier.py --data-source postgres --epochs 10"
echo "  2. Start API:        python api/inference_server.py"
echo "  3. Both (train then serve): bash run_all.sh"
echo ""
echo "The inference server will be available at: http://localhost:8000"
echo "POST /predict - send features to get predictions with activation_snapshot"
echo "POST /receive-training-data - forward events from dashboard send-template"
echo ""
echo "=== MNIST/RTX 5060 Optimization Notes ==="
echo " - For RTX 5060, enable mixed precision for faster training"
echo " - Batch size 32 is optimal for 8GB VRAM"
echo " - Use CICIDS2017 + lab-generated attacks for best results"
echo " - activation_snapshot is mandatory - always included in /predict response"
echo ""
echo "=== Data Flow from Dashboard ==="
echo "  1. Dashboard reads events from PostgreSQL via GET /api/v1/events"
echo "  2. User selects events and clicks 'Send Template'"
echo "  3. Dashboard POSTs to http://<laptop-ip>:8000/receive-training-data"
echo "  4. Laptop API processes events and updates class labels"
echo "  5. User runs training script to train on new data"
echo "  6. New model weights are saved and can be loaded by fusion module"
echo ""
echo "========================================"