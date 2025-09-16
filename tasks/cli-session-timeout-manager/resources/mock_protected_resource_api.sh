#!/bin/bash

# Mock Protected Resource API for cli-session-timeout-manager task
# Simulates an API endpoint that requires a valid Bearer token.

LOG_FILE="mock_protected_api.log"
# This mock API will call the mock_auth_api.sh's /validate endpoint
# to check token validity.
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOCK_AUTH_API_SCRIPT="$SCRIPT_DIR/mock_auth_api.sh" # Path to the auth API mock

log_protected_api() {
    echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MOCK_PROTECTED_API] $1" >> "$LOG_FILE"
}

# --- Request Handling ---
# Expects Authorization: Bearer <token> header (passed via env var for mock)
# Input: Any data via stdin (optional, not used by this mock's logic but can be logged)

handle_request() {
    local request_body=""
    if [ -p /dev/stdin ]; then
        request_body=$(cat)
        log_protected_api "Received request with body: $request_body"
    else
        log_protected_api "Received request with no body."
    fi

    # Get token from Authorization header (simulated via env var)
    local auth_header="$HTTP_AUTHORIZATION" # e.g., "Bearer actual_token_value"
    echo "DEBUG: auth_header = '$auth_header'" >&2
    if [ -z "$auth_header" ] || [[ "$auth_header" != Bearer\ * ]]; then
        log_protected_api "Authorization header missing or not Bearer type. Header: '$auth_header'"
        echo '{"error": "unauthorized", "error_description": "Authorization header missing or invalid."}'
        return 401 # Unauthorized
    fi

    local token="${auth_header#Bearer }"
    echo "DEBUG: extracted token = '$token'" >&2
    log_protected_api "Extracted token: $token"

    # Validate token by calling the mock_auth_api.sh /validate endpoint
    # Pass token via stdin for mock_auth_api.sh to pick up
    local validation_response
    validation_response=$(echo "{\"access_token\": \"$token\"}" | "$MOCK_AUTH_API_SCRIPT" /validate)
    local validation_status_code=$?

    log_protected_api "Token validation response (Status $validation_status_code): $validation_response"

    if [ "$validation_status_code" -ne 0 ]; then # Auth API returned non-200, meaning token invalid/expired
        # The response from /validate already contains error details.
        # The protected API should typically return its own 401, possibly with info from auth validation.
        local error_detail_from_auth=$(echo "$validation_response" | jq -r '.error_description // "Token validation failed."')
        echo "$(jq -n --arg err "invalid_token" --arg desc "$error_detail_from_auth (from auth validation)" \
            '{error: $err, error_description: $desc}')"
        return 401 # Unauthorized
    fi

    # If validation_status_code was 0, check the 'valid' field in response
    local is_token_valid=$(echo "$validation_response" | jq -r '.valid // false')
    if [ "$is_token_valid" != "true" ]; then
        log_protected_api "Token reported as invalid by auth API."
         local error_detail_from_auth=$(echo "$validation_response" | jq -r '.error_description // "Token is not valid."')
        echo "$(jq -n --arg err "invalid_token" --arg desc "$error_detail_from_auth" \
            '{error: $err, error_description: $desc}')"
        return 401
    fi

    # Token is valid, proceed to serve resource
    local user_id=$(echo "$validation_response" | jq -r '.user_id // "unknown_user"')
    log_protected_api "Access granted for user '$user_id'. Serving protected resource."

    echo "$(jq -n --arg uid "$user_id" --arg data "This is a super secret resource for user $uid. Timestamp: $(date +%s)" \
        '{user_id: $uid, message: "Access granted to protected resource.", data: $data}')"
    return 0 # HTTP OK
}


# --- Main ---
log_protected_api "Protected Resource API script started."

# Simulate different HTTP methods if needed, for now, assume GET or POST to one endpoint
# The actual HTTP method isn't used by this simple mock's logic.

# Call the main handler
handle_request
HTTP_STATUS_CODE=$?


log_protected_api "Protected Resource API script finished with HTTP status $HTTP_STATUS_CODE."
exit $HTTP_STATUS_CODE
