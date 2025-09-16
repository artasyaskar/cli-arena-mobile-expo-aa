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

# Function to print success messages
success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Function to print error messages
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

# 2. Run Go unit tests
echo "2. Running Go unit tests..."
if (cd app && go test ./...); then
    success "Go unit tests passed."
else
    error "Go unit tests failed. Please check the test output."
fi

# 3. Check if the Docker image was built
echo "3. Checking for the local Docker image 'k8s-crash-app:latest'..."
if docker image inspect k8s-crash-app:latest > /dev/null 2>&1; then
    success "Docker image 'k8s-crash-app:latest' was found."
else
    error "The Docker image 'k8s-crash-app:latest' was not found. Did you build and tag it?"
fi

# 4. Check Kubernetes deployment status
echo "4. Checking the Kubernetes deployment..."
kubectl apply -f k8s/ > /dev/null
echo "   Waiting for deployment 'k8s-crash-app-deployment' to be ready..."
if ! kubectl wait --for=condition=available --timeout=60s deployment/k8s-crash-app-deployment; then
    error "Deployment did not become available in time. Check pod status with 'kubectl get pods'."
    kubectl get pods -l app=k8s-crash-app --no-headers
fi

# 5. Verify pod logging
echo "5. Verifying pod logs..."
POD_NAME=$(kubectl get pods -l app=k8s-crash-app -o jsonpath="{.items[0].metadata.name}")
if kubectl logs $POD_NAME | grep -q "Starting server on port 8080"; then
    success "Pod logs contain the expected startup message."
else
    error "Pod logs do not contain the expected 'Starting server' message."
    echo "--- Pod Logs ---"
    kubectl logs $POD_NAME
fi

# 6. Check if the service is accessible
echo "6. Checking if the service is accessible..."
SERVICE_NAME="k8s-crash-app-service"
kubectl port-forward svc/$SERVICE_NAME 8081:8080 > /tmp/port-forward.log 2>&1 &
PORT_FORWARD_PID=$!
sleep 3

if curl -s http://localhost:8081 | grep -q "Hello, World!"; then
    success "Service is accessible and returns the correct content."
else
    error "Could not connect to the service, or it returned an unexpected response."
fi
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
