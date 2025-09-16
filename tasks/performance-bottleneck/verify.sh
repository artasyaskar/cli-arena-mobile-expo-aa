#!/usr/bin/env bash
set -euo pipefail

echo "🔥 Verifying 'Optimize the Slow API Endpoint' Task"
echo "================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

FAILED=0

# Create a Dockerfile for the app
cat > app/Dockerfile <<'DOCKERFILE'
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["gunicorn", "--workers", "4", "--bind", "0.0.0.0:5000", "app:app"]
DOCKERFILE
# Add gunicorn to requirements for a multi-worker server
echo "gunicorn==20.1.0" >> app/requirements.txt


# 1. Run unit tests on the user's submitted code
echo "1. Running unit tests..."
# We need to install dependencies to run the tests
pip install -r app/requirements.txt > /dev/null
if python3 -m unittest app/test_app.py; then
    echo -e "${GREEN}✅ Unit tests passed.${NC}"
else
    echo -e "${RED}❌ Unit tests failed. The core logic might be broken.${NC}"
    FAILED=1
fi


# --- 2. Benchmark the original, slow application ---
echo "2. Benchmarking the original (slow) application..."
git checkout -- app/app.py
docker build -t slow-app -f app/Dockerfile ./app > /dev/null
docker run -d --rm --name slow-app-container -p 5000:5000 slow-app
sleep 5

ORIGINAL_TIME=$(python3 app/benchmark.py | awk '{print $6}')
echo "   Original response time: $ORIGINAL_TIME seconds"
docker stop slow-app-container > /dev/null


# --- 3. Benchmark the user's fixed application ---
echo "3. Benchmarking the user's fixed application..."
# The user's modified app.py is already in place from the unit test step
docker build -t fast-app -f app/Dockerfile ./app > /dev/null
docker run -d --rm --name fast-app-container -p 5000:5000 fast-app
sleep 5

FIXED_TIME=$(python3 app/benchmark.py | awk '{print $6}')
echo "   Fixed response time: $FIXED_TIME seconds"
docker stop fast-app-container > /dev/null


# --- 4. Compare the results ---
echo "4. Comparing performance..."
IMPROVEMENT_FACTOR=$(echo "$ORIGINAL_TIME / $FIXED_TIME" | bc -l)
echo "   Performance improvement factor: ${IMPROVEMENT_FACTOR}x"

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
