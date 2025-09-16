#!/bin/bash

# example_cli_tool.sh
# Demonstrates usage of the cli-localized-error-capture framework.

# --- Source the Framework ---
# Determine script's own directory to find solution.sh relative to it.
# This makes it runnable from any location if example_cli_tool.sh and solution.sh are in the same dir.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
ERROR_FRAMEWORK_PATH="$SCRIPT_DIR/solution.sh" # Adjust if solution.sh is elsewhere

if [ -f "$ERROR_FRAMEWORK_PATH" ]; then
    # shellcheck source=solution.sh
    source "$ERROR_FRAMEWORK_PATH"
else
    echo "CRITICAL: Error reporting framework ($ERROR_FRAMEWORK_PATH) not found." >&2
    exit 127
fi

# Optional: Enable debug logging for the error framework itself
# export ERRFW_DEBUG="true"

# --- Example CLI Tool Logic ---

# Function to simulate an operation that might fail
perform_file_operation() {
    local filename="$1"
    local operation="$2"

    echo "[Example Tool] Attempting to $operation file: $filename"

    if [ -z "$filename" ]; then
        # Report E_INVALID_INPUT error using the framework
        # Parameters are passed as "key=value" strings
        report_error "E_INVALID_INPUT" "field=filename" "reason=cannot be empty"
        return 2 # Specific exit code for this app's logic
    fi

    if [ "$filename" == "nonexistent.txt" ] && [ "$operation" == "read" ]; then
        # Report E_FILE_NOT_FOUND
        report_error "E_FILE_NOT_FOUND" "filename=$filename" "operation=$operation"
        return 3
    fi

    if [ "$filename" == "secret.doc" ] && [ "$operation" == "read" ]; then
        # Report E_PERMISSION_DENIED
        report_error "E_PERMISSION_DENIED" "resource=$filename" "username=$(whoami)"
        return 4
    fi

    if [ "$operation" == "upload" ]; then
        # Report E_NETWORK_UNAVAILABLE (simulated)
        report_error "E_NETWORK_UNAVAILABLE"
        return 5
    fi

    # If successful
    # Report I_OPERATION_SUCCESSFUL (informational, report_error still returns 1 by default from framework)
    report_error "I_OPERATION_SUCCESSFUL" "operation=$operation" "target=$filename"
    # Example tool decides if this "error" (from framework's perspective) is a real failure.
    # For informational, we might not want to exit with error.
    echo "[Example Tool] Successfully performed $operation on $filename (according to this tool's logic)."
    return 0 # Success for this tool
}

# Main part of the example tool
echo "Example CLI Tool Started."
echo "Simulating various operations and errors..."
echo "------------------------------------------"

# Simulate different scenarios
echo "Scenario 1: Reading a non-existent file"
perform_file_operation "nonexistent.txt" "read"
echo "Exit code from Scenario 1: $?"
echo "------------------------------------------"

echo "Scenario 2: Reading a 'secret' file (permission denied)"
perform_file_operation "secret.doc" "read"
echo "Exit code from Scenario 2: $?"
echo "------------------------------------------"

echo "Scenario 3: Uploading a file (network unavailable)"
perform_file_operation "mydata.zip" "upload"
echo "Exit code from Scenario 3: $?"
echo "------------------------------------------"

echo "Scenario 4: Invalid input (empty filename)"
perform_file_operation "" "process"
echo "Exit code from Scenario 4: $?"
echo "------------------------------------------"

echo "Scenario 5: Unknown error code from application"
report_error "E_APP_SPECIFIC_MYSTERY" "detail=Cosmic rays" "component=CoreLogic"
echo "Exit code from Scenario 5 (report_error): $?"
echo "------------------------------------------"

echo "Scenario 6: Successful operation (informational message)"
perform_file_operation "document.pdf" "verify"
echo "Exit code from Scenario 6: $?"
echo "------------------------------------------"


echo "Example CLI Tool Finished."
# The overall exit code of this script will be that of the last command.
# A real tool would manage its exit code more carefully.
exit 0
