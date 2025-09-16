#!/usr/bin/env bash
# This script provides the solution for the 'ci-pipeline-fix' task.

set -euo pipefail

echo "Solving the 'ci-pipeline-fix' task..."

# 1. Fix the logical bug in the subtract function
echo "Fixing the unit test bug in app/main.py..."
sed -i "s/return a + b/return a - b/g" app/main.py

# 2. Fix the linting error by removing the unused import
echo "Fixing the linting error in app/main.py..."
sed -i "/import os/d" app/main.py

# 3. Fix the security vulnerability by updating the dependency
echo "Fixing the security vulnerability in app/requirements.txt..."
sed -i "s/PyYAML==5.3/PyYAML==6.0/g" app/requirements.txt

echo "All issues have been fixed."
echo "Running the pipeline to confirm..."

# Run the verify script (which runs the pipeline) to show it passes
./verify.sh
