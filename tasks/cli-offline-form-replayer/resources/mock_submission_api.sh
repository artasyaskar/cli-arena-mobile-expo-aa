#!/bin/bash

# Mock Submission API for cli-offline-form-replayer task

API_LOG_FILE="mock_submission_api.log"
# Simple file to store submitted "unique IDs" to simulate conflict detection
SUBMITTED_IDS_DB="${MOCK_SUBMISSION_DB:-./mock_submitted_ids.txt}"

log_api() {
    echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MOCK_SUBMISSION_API] $1" >> "$API_LOG_FILE"
}

# Ensure DB file exists
touch "$SUBMITTED_IDS_DB"

# --- Request Handling ---
# Expects POST request with JSON body
# JSON body should contain form data, including a field used for uniqueness check (e.g., 'submission_guid' or a hash of content)

handle_submission() {
    local request_body
    request_body=$(cat) # Read JSON from stdin

    log_api "Received submission: $request_body"

    # Simulate network instability or server load
    if [ -n "$SIMULATE_API_ERROR_RATE" ] && [ "$(shuf -i 1-100 -n 1)" -le "$SIMULATE_API_ERROR_RATE" ]; then
        local error_type=$((RANDOM % 2))
        if [ $error_type -eq 0 ]; then
            log_api "Simulating transient server error (500 Internal Server Error)"
            echo '{"error": "Internal Server Error", "message": "A temporary issue occurred on the server."}'
            return 500
        else
            log_api "Simulating service unavailable (503 Service Unavailable)"
            echo '{"error": "Service Unavailable", "message": "The server is temporarily unable to handle the request."}'
            return 503
        fi
    fi

    # Validate incoming JSON (basic check)
    if ! echo "$request_body" | jq -e . > /dev/null 2>&1; then
        log_api "Invalid JSON payload received."
        echo '{"error": "Bad Request", "message": "Invalid JSON format."}'
        return 400
    fi

    # Extract a field for uniqueness check (e.g., a client-generated GUID or a hash of key fields)
    # For this mock, let's assume the client sends a 'client_submission_id' field.
    local client_submission_id=$(echo "$request_body" | jq -r '.client_submission_id // ""')
    local form_id=$(echo "$request_body" | jq -r '.formId // "unknown_form"')

    if [ -z "$client_submission_id" ]; then
        log_api "Submission missing 'client_submission_id'."
        echo '{"error": "Bad Request", "message": "Missing client_submission_id field."}'
        return 400
    fi

    # Simulate server-side validation based on formId (very basic)
    if [ "$form_id" == "issue_report_v2" ]; then
        local summary=$(echo "$request_body" | jq -r '.formData.issue_summary // ""')
        if [ -z "$summary" ] || [ "${#summary}" -lt 5 ]; then
            log_api "Server-side validation failed for issue_report_v2: summary too short."
            echo "$(jq -n --arg field "issue_summary" --arg reason "Summary must be at least 5 characters." \
                '{error: "Validation Error", message: "Invalid data submitted.", details: [{field: $field, error: $reason}]}')"
            return 400
        fi
    fi


    # Conflict Check: See if this client_submission_id has been processed before
    if grep -Fxq "$client_submission_id" "$SUBMITTED_IDS_DB"; then
        log_api "Conflict: Submission ID '$client_submission_id' already processed."
        echo '{"error": "Conflict", "message": "This submission has already been processed (duplicate client_submission_id)."}'
        return 409 # Conflict
    fi

    # Simulate processing delay
    sleep $((RANDOM % 3 + 1)) # Sleep 1-3 seconds

    # If all checks pass, simulate successful submission
    echo "$client_submission_id" >> "$SUBMITTED_IDS_DB" # Record as processed
    local server_assigned_id="SERVER_ID_$(date +%s%N)"
    log_api "Submission '$client_submission_id' processed successfully. Server ID: $server_assigned_id"

    echo "$(jq -n --arg sid "$server_assigned_id" --arg cid "$client_submission_id" \
        '{status: "success", message: "Submission received and processed.", server_id: $sid, client_submission_id: $cid}')"
    return 201 # Created
}

# --- Main ---
log_api "Mock Submission API script started."

# This mock only handles POST requests to a generic /submit endpoint
if [ "$REQUEST_METHOD" == "POST" ]; then # Assume REQUEST_METHOD is set by curl or test harness
    handle_submission
    exit $?
else
    log_api "Unsupported method: $REQUEST_METHOD. Only POST is supported."
    echo '{"error": "Method Not Allowed", "message": "Only POST requests are supported."}'
    exit 405 # Method Not Allowed
fi

# Fallback exit, should be covered by cases above
exit 1
