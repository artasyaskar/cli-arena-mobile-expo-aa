#!/usr/bin/env bash
set -euo pipefail

echo "🔥 Verifying 'Fix the Broken CI/CD Pipeline' Task"
echo "================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Make sure the pipeline script is executable
chmod +x ./ci_pipeline.sh

echo "Running the CI pipeline to verify the fixes..."

# Run the pipeline and capture the output
if ./ci_pipeline.sh; then
  echo -e "\n${GREEN}✅ Success! The CI pipeline ran successfully.${NC}"
  exit 0
else
  echo -e "\n${RED}❌ Failure. The CI pipeline script failed. Make sure all stages are passing.${NC}"
  exit 1
fi
