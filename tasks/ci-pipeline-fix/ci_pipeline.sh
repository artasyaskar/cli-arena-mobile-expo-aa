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
# Added --max-line-length to make the check stricter
if flake8 app/ --max-line-length=88; then
  echo "✅ Linter passed."
else
  echo "❌ Linter failed with style issues."
  exit 1
fi

# --- Stage 3: Security Scan ---
echo -e "\n🛡️ Running Security Scan..."
VULNERABLE_VERSION_FOUND=0
# More robust check for vulnerable PyYAML version
PYYAML_VERSION=$(grep "PyYAML" app/requirements.txt | sed 's/==/ /g' | awk '{print $2}')
if [[ -n "$PYYAML_VERSION" ]]; then
    # Use sort -V to compare versions
    if ! printf '%s\n' "5.4" "$PYYAML_VERSION" | sort -V -C; then
        echo "❌ Security scan failed: Vulnerable dependency 'PyYAML' version '$PYYAML_VERSION' found. Please update to 5.4 or higher."
        VULNERABLE_VERSION_FOUND=1
    fi
fi

if [ $VULNERABLE_VERSION_FOUND -eq 1 ]; then
    exit 1
else
    echo "✅ Security scan passed."
fi


echo -e "\n🎉 CI Pipeline Finished Successfully!"
