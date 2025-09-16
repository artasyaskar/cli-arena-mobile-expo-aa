#!/bin/bash
# Sample job script that succeeds

echo "Sample Success Job: Starting execution."
echo "Arguments received: $@"
echo "Current directory: $(pwd)"
echo "User: $(whoami)"
echo "Simulating some work for 3 seconds..."
sleep 3
echo "Sample Success Job: Work completed."
echo "This is some output to STDOUT."
echo "Another line to STDOUT."

# Simulate some stderr output as well, even on success
echo "Sample Success Job: This is a message to STDERR, but job will succeed." >&2

echo "Sample Success Job: Finished successfully."
exit 0
