#!/bin/bash

# ELK Stack Deployment Script for k3s
# This script deploys Elasticsearch, Logstash, and Kibana to k3s
# Optimized for direct log ingestion without Filebeat

set -e

echo "🚀 Starting ELK Stack deployment on k3s (without Filebeat)..."

# Check if k3s is running
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install k3s first."
    exit 1
fi

# Check if k3s cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to k3s cluster. Please ensure k3s is running."
    exit 1
fi

echo "✅ k3s cluster is accessible"

# Apply namespace first
echo "📁 Creating namespace..."
kubectl apply -f namespace.yaml

# Wait for namespace to be ready (with better error handling)
echo "⏳ Waiting for namespace to be ready..."
if ! kubectl wait --for=condition=Ready --timeout=60s namespace/elk-stack 2>/dev/null; then
    echo "⚠️  Namespace condition check timed out, but continuing (this is usually fine)..."
    # Give it a moment and check if namespace exists
    sleep 5
    if kubectl get namespace elk-stack >/dev/null 2>&1; then
        echo "✅ Namespace exists and is usable"
    else
        echo "❌ Namespace creation failed"
        exit 1
    fi
else
    echo "✅ Namespace is ready"
fi

# Apply storage resources
echo "💾 Setting up storage..."
kubectl apply -f elasticsearch-storage.yaml

# Apply credentials first
echo "🔐 Setting up authentication credentials..."
kubectl apply -f elk-credentials.yaml

# Apply configuration maps
echo "⚙️  Applying configurations..."
kubectl apply -f elasticsearch-config.yaml
kubectl apply -f logstash-config-fixed.yaml
kubectl apply -f kibana-config.yaml


# Deploy Elasticsearch first
echo "🔍 Deploying Elasticsearch..."
kubectl apply -f elasticsearch.yaml

# Wait for Elasticsearch to be ready
echo "⏳ Waiting for Elasticsearch to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/elasticsearch -n elk-stack

# Check if Elasticsearch is healthy
echo "🏥 Checking Elasticsearch health..."
kubectl wait --for=condition=ready --timeout=300s pod -l app=elasticsearch -n elk-stack

# Setup Elasticsearch users
echo "👤 Setting up Elasticsearch users..."
kubectl apply -f elasticsearch-user-setup.yaml

# Wait for user setup job to complete
echo "⏳ Waiting for user setup to complete..."
kubectl wait --for=condition=complete --timeout=300s job/elasticsearch-setup-users -n elk-stack

# Create binance persistent volume claim
echo "📦 Creating Binance shared PVC..."
kubectl apply -f binance-shared-pvc.yaml

# Deploy Logstash
echo "📊 Deploying Logstash..."
kubectl apply -f logstash.yaml

# Wait for Logstash to be ready
echo "⏳ Waiting for Logstash to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/logstash -n elk-stack

# Setup Kibana system configuration
echo "⚙️  Setting up Kibana system configuration..."
kubectl apply -f kibana-system-setup.yaml

# Wait for Kibana system setup to complete
echo "⏳ Waiting for Kibana system setup to complete..."
kubectl wait --for=condition=complete --timeout=300s job/kibana-system-setup -n elk-stack

# Deploy Kibana
echo "📈 Deploying Kibana..."
kubectl apply -f kibana.yaml

# Wait for Kibana to be ready
echo "⏳ Waiting for Kibana to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/kibana -n elk-stack

# Apply ingress rules
echo "🌐 Setting up ingress..."
kubectl apply -f ingress.yaml

echo "✅ ELK Stack deployment completed with authentication!"
echo ""
echo "� Authentication Information:"
echo "   Username: chater"
echo "   Password: Protel2025!"
echo "   Elastic Username: elastic"
echo "   Elastic Password: Protel2025!"
echo ""
echo "�📊 Deployment Status:"
kubectl get pods -n elk-stack
echo ""
echo "🌐 Access URLs (add these to your /etc/hosts file):"
echo "   Kibana: http://kibana.local (Login with chater:Protel2025!)"
echo "   Elasticsearch: http://elasticsearch.local (Login with chater:Protel2025!)"
echo "   Logstash: http://logstash.local"
echo ""
echo "💡 To add entries to /etc/hosts, run:"
echo "   echo '$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type==\"InternalIP\")].address}') kibana.local elasticsearch.local logstash.local' | sudo tee -a /etc/hosts"
echo ""
echo "🔍 To check logs:"
echo "   kubectl logs -f deployment/elasticsearch -n elk-stack"
echo "   kubectl logs -f deployment/logstash -n elk-stack"
echo "   kubectl logs -f deployment/kibana -n elk-stack"
echo ""
echo "📊 To send test data:"
echo "   curl -X POST http://logstash.local:8080 -H 'Content-Type: application/json' -d '{\"message\":\"test log\"}'"
echo "   echo '{\"message\":\"test log\"}' | nc logstash.local 5000"
echo ""
echo "🗑️  To cleanup:"
echo "   kubectl delete namespace elk-stack"

# Optional: Deploy Binance WebSocket backend
if [[ "$1" == "--with-binance" ]]; then
    echo ""
    echo "🏦 Deploying Binance WebSocket backend..."
    
    # Check if Docker is available for building the image
    if command -v docker &> /dev/null; then
        echo "  📦 Building Binance backend Docker image..."
        cd binance-backend
        docker build -t binance-backend:latest .
        cd ..
        
        echo "  ⚙️  Deploying Binance components..."
        kubectl apply -f binance-shared-pvc.yaml
        kubectl apply -f binance-backend.yaml
        
        echo "  ⏳ Waiting for Binance backend to be ready..."
        kubectl wait --for=condition=available --timeout=300s deployment/binance-backend -n elk-stack
        
        echo "  ✅ Binance WebSocket backend deployed!"
        echo "  📊 Monitor with: kubectl logs -f deployment/binance-backend -n elk-stack"
    else
        echo "  ⚠️  Docker not found. Skipping Binance backend deployment."
        echo "  💡 To deploy later: ./deploy-binance.sh"
    fi
fi
