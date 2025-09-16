#!/usr/bin/env bash
set -eo pipefail

echo "🚀 Starting CI Pipeline..."

# --- Setup ---
# Create a virtual environment and install dependencies
python3 -m venv venv
source venv/bin/activate
pip install -r app/requirements.txt

# --- Stage 1: Run Unit Tests ---
echo -e "\n🧪 Running Unit Tests..."
if python3 -m unittest app/test_main.py; then
  echo "✅ Unit tests passed."
else
  echo "❌ Unit tests failed."
  exit 1
fi

# --- Stage 2: Linting ---
echo -e "\n🎨 Running Linter (flake8)..."
if flake8 app/; then
  echo "✅ Linter passed."
else
  echo "❌ Linter failed with style issues."
  exit 1
fi

# --- Stage 3: Security Scan ---
echo -e "\n🛡️ Running Security Scan..."
# This is a mock scanner that checks for a specific vulnerable package.
if grep -q "PyYAML==5.3" app/requirements.txt; then
  echo "❌ Security scan failed: Vulnerable dependency 'PyYAML==5.3' found."
  exit 1
else
  echo "✅ Security scan passed."
fi

echo -e "\n🎉 CI Pipeline Finished Successfully!"
