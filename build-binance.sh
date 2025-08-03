#!/bin/bash

# Build script for Binance WebSocket Backend

echo "Building Binance WebSocket Docker image..."

# Build the Docker image
docker build -t binance-websocket:latest ./binance-backend/

if [ $? -eq 0 ]; then
    echo "✅ Docker image built successfully: binance-websocket:latest"
    echo ""
    echo "Next steps:"
    echo "1. Apply the shared PVC: kubectl apply -f binance-shared-pvc.yaml"
    echo "2. Deploy the backend: kubectl apply -f binance-backend.yaml"
    echo "3. Update Logstash: kubectl apply -f logstash-config.yaml && kubectl apply -f logstash.yaml"
    echo ""
    echo "Or run the deployment script: ./deploy-binance.sh"
else
    echo "❌ Failed to build Docker image"
    exit 1
fi
