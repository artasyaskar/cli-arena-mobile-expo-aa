#!/usr/bin/env bash
set -euo pipefail

echo "🔥 Verifying 'Optimize the Slow API Endpoint' Task"
echo "================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

# Create a Dockerfile for the app
cat > app/Dockerfile <<'DOCKERFILE'
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["flask", "run", "--host=0.0.0.0"]
DOCKERFILE

# --- 1. Benchmark the original, slow application ---
echo "1. Benchmarking the original (slow) application..."
# First, restore the original app.py to get an accurate baseline
git checkout -- app/app.py

docker build -t slow-app -f app/Dockerfile ./app > /dev/null
docker run -d --rm --name slow-app-container -p 5000:5000 slow-app
sleep 5 # Wait for the app to start

# Run the benchmark
ORIGINAL_TIME=$(python3 app/benchmark.py | awk '{print $3}')
echo "   Original response time: $ORIGINAL_TIME seconds"
docker stop slow-app-container > /dev/null

# --- 2. Benchmark the user's fixed application ---
echo "2. Benchmarking the user's fixed application..."
# The user's modified app.py is already in place
docker build -t fast-app -f app/Dockerfile ./app > /dev/null
docker run -d --rm --name fast-app-container -p 5000:5000 fast-app
sleep 5 # Wait for the app to start

# Run the benchmark
FIXED_TIME=$(python3 app/benchmark.py | awk '{print $3}')
echo "   Fixed response time: $FIXED_TIME seconds"
docker stop fast-app-container > /dev/null

# --- 3. Compare the results ---
echo "3. Comparing performance..."
# Using 'bc' for floating point arithmetic
IMPROVEMENT_FACTOR=$(echo "$ORIGINAL_TIME / $FIXED_TIME" | bc -l)

echo "   Performance improvement factor: ${IMPROVEMENT_FACTOR}x"

# Check if the improvement is at least 10x
if (( $(echo "$IMPROVEMENT_FACTOR > 10" | bc -l) )); then
    echo -e "${GREEN}✅ Success! The performance improvement is greater than 10x.${NC}"
else
    echo -e "${RED}❌ Failure. The performance improvement is less than 10x.${NC}"
    FAILED=1
fi

# --- Final Summary ---
echo "------------------------------------------------------"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All verification checks passed! Great optimization work!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some verification checks failed. Please review the errors above.${NC}"
    exit 1
fi
