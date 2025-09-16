#!/usr/bin/env bash
# This script provides the solution for the 'k8s-crash-debug' task.

set -euo pipefail

echo "Solving the 'k8s-crash-debug' task..."

# 1. Fix the bug in the Go application.
# The bug is the line `configPath := os.Args[1]`. We can safely remove it.
# A more robust fix would check the length of os.Args, but for this simple
# app, removing it is the cleanest solution.
echo "Fixing the Go source code in app/main.go..."
sed -i "/configPath := os.Args\[1\]/d" app/main.go
sed -i "/fmt.Println(\"Loading config from:\", configPath)/d" app/main.go

echo "Fixed code:"
cat app/main.go

# 2. Build the Docker image.
# We need to build it from the 'app' directory and tag it correctly.
echo "Building the Docker image 'k8s-crash-app:latest'..."
docker build -t k8s-crash-app:latest ./app

# 3. Load the image into the local Kubernetes cluster (e.g., kind).
# This step is necessary so the cluster can find the image without a registry.
echo "Loading the Docker image into the 'kind' cluster..."
kind load docker-image k8s-crash-app:latest

# 4. Deploy the application to Kubernetes.
echo "Applying the Kubernetes manifests..."
kubectl apply -f ./k8s

echo "Solution applied. Run the verify.sh script to check your work."
