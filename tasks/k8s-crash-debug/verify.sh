#!/usr/bin/env bash
set -euo pipefail

echo "🔥 Verifying 'Fix the Crashing Kubernetes Service' Task"
echo "======================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0
SUCCESS_COUNT=0

# Function to print success messages
success() {
    echo -e "${GREEN}✅ $1${NC}"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
}

# Function to print error messages
# Exits the script if the error is fatal
fatal_error() {
    echo -e "${RED}❌ $1${NC}"
    echo "Verification failed."
    exit 1
}

error() {
    echo -e "${RED}❌ $1${NC}"
    FAILED=1
}

# --- Verification Steps ---

# 1. Check the source code fix
echo "1. Checking Go source code for the fix..."
if ! grep -q "os.Args" app/main.go || grep -q "len(os.Args)" app/main.go; then
    success "Go source code appears to be fixed (no longer panics on os.Args)."
else
    error "The bug in app/main.go doesn't seem to be fixed. The code might still panic."
fi

# 2. Check if the Docker image was built
echo "2. Checking for the local Docker image 'k8s-crash-app:latest'..."
if docker image inspect k8s-crash-app:latest > /dev/null 2>&1; then
    success "Docker image 'k8s-crash-app:latest' was found."
else
    error "The Docker image 'k8s-crash-app:latest' was not found. Did you build and tag it?"
fi

# 3. Check Kubernetes deployment status
echo "3. Checking the Kubernetes deployment..."
# First, apply the manifests to be sure they are in the cluster
if ! kubectl apply -f k8s/ > /dev/null; then
    fatal_error "Could not apply Kubernetes manifests. Is kubectl configured correctly?"
fi

# Wait for the deployment to be ready
echo "   Waiting for deployment 'k8s-crash-app-deployment' to be ready..."
if kubectl wait --for=condition=available --timeout=60s deployment/k8s-crash-app-deployment; then
    success "Deployment 'k8s-crash-app-deployment' is available and running."
else
    error "Deployment did not become available in time. Check pod status with 'kubectl get pods'."
    kubectl get pods -l app=k8s-crash-app --no-headers
fi

# 4. Check if the service is accessible
echo "4. Checking if the service is accessible..."
SERVICE_NAME="k8s-crash-app-service"
# Using port-forward to create a stable access point to the service
kubectl port-forward svc/$SERVICE_NAME 8081:8080 > /tmp/port-forward.log 2>&1 &
PORT_FORWARD_PID=$!
# Give it a moment to start
sleep 3

if curl -s http://localhost:8081 | grep -q "Hello, World!"; then
    success "Service is accessible and returns the correct content."
else
    error "Could not connect to the service, or it returned an unexpected response."
    echo "--- Port-forward logs ---"
    cat /tmp/port-forward.log
fi

# Cleanup port-forwarding
kill $PORT_FORWARD_PID > /dev/null 2>&1 || true


# --- Final Summary ---
echo "------------------------------------------------------"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All verification checks passed! Great job!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some verification checks failed. Please review the errors above.${NC}"
    exit 1
fi
