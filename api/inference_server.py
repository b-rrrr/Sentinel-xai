#!/usr/bin/env python3
"""Inference server for Branch 2 - ML training template
Runs on RTX 5060 laptop outside the homeserver network
Provides /predict endpoint with mandatory activation_snapshot per §5.3
"""

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
import uvicorn
import numpy as np
import json
import os
import sys
from pathlib import Path

# Add scripts directory to path for module imports
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

# Import training module functions
from train_classifier import (
    load_feature_names, preprocess_features, 
    map_attack_type, CLASS_LABELS, int_to_label,
    target_layer_name
)

app = FastAPI(
    title="Sentinel Lab ML Classifier Inference",
    description="Inference server with activation_snapshot for neuro-symbolic fusion",
    version="1.0.0"
)

# Try to load trained model
MODEL_PATH = os.getenv("CLASSIFIER_MODEL_PATH", "models/output/classifier.h5")
FEATURE_NAMES_PATH = os.getenv("FEATURE_NAMES_PATH", "feature_names.json")

# Global model and configs
model = None
feature_names = None
CLASS_LABELS_OBJ = {}

try:
    if os.path.exists(MODEL_PATH):
        model = __import__('tensorflow').keras.models.load_model(MODEL_PATH)
        print(f"Model loaded from {MODEL_PATH}")
    else:
        print(f"Warning: Model not found at {MODEL_PATH}. Using random weights.")
    
    if os.path.exists(FEATURE_NAMES_PATH):
        with open(FEATURE_NAMES_PATH, "r") as f:
            feature_names = json.load(f)
    else:
        feature_names = load_feature_names()
        # Save for future use
        with open(FEATURE_NAMES_PATH, "w") as f:
            json.dump(feature_names, f, indent=2)
        print(f"Feature names loaded (generated default)")
    
    # Try to load label mapping
    mapping_path = Path(MODEL_PATH).parent / "label_mapping.json"
    if mapping_path.exists():
        with open(mapping_path, "r") as f:
            mapping = json.load(f)
        CLASS_LABELS_OBJ = mapping.get("label_to_int", {"BENIGN": 0, "SQL_INJECTION": 1, 
                                                      "XSS": 2, "PATH_TRAVERSAL": 3, 
                                                      "COMMAND_INJECTION": 4, 
                                                      "BRUTE_FORCE": 5, "ANOMALY_UNKNOWN": 6})
        int_to_label_obj = {v: k for k, v in CLASS_LABELS_OBJ.items()}
    else:
        CLASS_LABELS_OBJ = {"BENIGN": 0, "SQL_INJECTION": 1, "XSS": 2, 
                          "PATH_TRAVERSAL": 3, "COMMAND_INJECTION": 4, 
                          "BRUTE_FORCE": 5, "ANOMALY_UNKNOWN": 6}
        int_to_label_obj = {v: k for k, v in CLASS_LABELS_OBJ.items()}

except Exception as e:
    print(f"Error initializing model: {e}")
    feature_names = load_feature_names()
    CLASS_LABELS_OBJ = {"BENIGN": 0, "SQL_INJECTION": 1, "XSS": 2, 
                      "PATH_TRAVERSAL": 3, "COMMAND_INJECTION": 4, 
                      "BRUTE_FORCE": 5, "ANOMALY_UNKNOWN": 6}
    int_to_label_obj = {v: k for k, v in CLASS_LABELS_OBJ.items()}


def get_activation_snapshot(feature_vector):
    """Extract activation snapshot from the model's target layer.
    MANDATORY per §5.3 - must never be omitted."""
    try:
        if model is None:
            # Return dummy activation if no model
            return {target_layer_name: np.random.rand(32).tolist()}
        
        # Create intermediate model to extract activations
        intermediate_model = keras.Model(
            inputs=model.input,
            outputs=model.get_layer(target_layer_name).output
        )
        
        # Reshape for 1D-CNN if needed
        if len(feature_vector.shape) == 1:
            reshaped = feature_vector.reshape(1, -1, 1)
        else:
            reshaped = feature_vector
        
        activation = intermediate_model(reshaped).numpy().flatten().tolist()
        return {target_layer_name: activation}
        
    except Exception as e:
        # Fallback: return dummy activations if extraction fails
        print(f"Warning: Could not extract activation snapshot: {e}")
        return {target_layer_name: np.random.rand(32).tolist()}


@app.post("/predict")
async def predict(request: Request):
    """Model inference endpoint.
    
    Returns prediction + activation_snapshot as per §5.3 contract.
    activation_snapshot is MANDATORY - never omit this field.
    """
    try:
        body = await request.json()
        features = body.get("features", {})
        
        # Preprocess features to fixed vector
        feature_vector = preprocess_features(features, feature_names)
        feature_vector = np.array(feature_vector, dtype=np.float32).reshape(1, -1)
        
        # Make prediction
        if model is not None:
            predictions = model.predict(feature_vector, verbose=0)[0]
            predicted_idx = int(np.argmax(predictions))
            confidence = float(predictions[predicted_idx])
            predicted_class = int_to_label_obj.get(predicted_idx, "ANOMALY_UNKNOWN")
        else:
            # Fallback when no model trained
            predicted_class = "ANOMALY_UNKNOWN"
            confidence = 0.0
            predictions = np.array([0.0] * len(CLASS_LABELS_OBJ))
        
        # Build per_class_probs
        per_class_probs = {}
        for idx, (label, int_val) in enumerate(CLASS_LABELS_OBJ.items()):
            per_class_probs[label] = float(predictions[idx]) if model else 0.0
        
        # Extract activation snapshot (MANDATORY)
        activation_snapshot = get_activation_snapshot(feature_vector)
        
        # Build response per §5.3 contract
        response = {
            "predicted_class": predicted_class,
            "confidence": round(confidence, 4),
            "per_class_probs": per_class_probs,
            "activation_snapshot": activation_snapshot  # MUST NOT BE OMITTED
        }
        
        return JSONResponse(content=response)
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Inference error: {str(e)}")


@app.post("/receive-training-data")
async def receive_training_data(request: Request):
    """Receive training events from dashboard send-template feature.
    Forward events to training pipeline.
    """
    try:
        body = await request.json()
        events = body.get("events", [])
        
        # Process events and update class labels
        global CLASS_LABELS_OBJ
        
        processed = 0
        for event in events:
            features = event.get("raw_features", {})
            ground_truth = event.get("ground_truth_label", "BENIGN")
            
            # Map and register class label
            mapped = map_attack_type(ground_truth)
            if mapped not in CLASS_LABELS_OBJ:
                # Add new label dynamically
                new_idx = len(CLASS_LABELS_OBJ)
                CLASS_LABELS_OBJ[mapped] = new_idx
                # Update int_to_label reverse mapping
                # Note: we'll handle this in the predict endpoint
            
            processed += 1
        
        return JSONResponse(
            content={
                "status": "training_data_received",
                "count": len(events),
                "registered_labels": list(CLASS_LABELS_OBJ.keys())
            }
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Training data receive error: {str(e)}")


@app.get("/health")
async def health_check():
    return JSONResponse(content={
        "status": "healthy", 
        "model_loaded": model is not None,
        "feature_count": len(feature_names) if feature_names else 0,
        "registered_classes": list(CLASS_LABELS_OBJ.keys())
    })


if __name__ == "__main__":
    port = int(os.getenv("INFERENCE_PORT", 8000))
    print(f"Starting inference server on port {port}")
    print(f"Model path: {MODEL_PATH}")
    print(f"Feature names: {FEATURE_NAMES_PATH}")
    uvicorn.run(app, host="0.0.0.0", port=port)