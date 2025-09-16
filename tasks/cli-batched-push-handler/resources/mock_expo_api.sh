#!/bin/bash

# Mock Expo Push API server
# Handles batches of push notifications and simulates various responses.

LOG_FILE="mock_expo_api.log"
# State file to simulate rate limiting persistence across calls if needed (optional)
# RATE_LIMIT_STATE_FILE="mock_expo_api_rate_state.json"

log_api() {
    echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MOCK_EXPO_API] $1" >> "$LOG_FILE"
}

# Simulate API key check (very basic)
# Expected: Authorization: Bearer <some_token> or token=<some_token> in query/body
MOCK_API_KEY="test-expo-api-key"

check_auth() {
    # This is a mock, so we're not actually parsing HTTP headers.
    # The solution script should pass the key in a conventional way.
    # Let's assume it's passed as an environment variable for simplicity in the mock.
    if [ -z "$EXPO_ACCESS_TOKEN" ] || [ "$EXPO_ACCESS_TOKEN" != "$MOCK_API_KEY" ]; then
        log_api "ERROR: Authentication failed. Missing or invalid EXPO_ACCESS_TOKEN."
        echo '{
            "errors": [{
                "code": "API_ERROR",
                "message": "Authentication failed. Invalid API key."
            }]
        }'
        exit 401 # Unauthorized
    fi
    log_api "Authentication successful."
}

# --- Request Handling ---
# Input: JSON array of notification objects, piped via stdin
# Each notification: { "to": "ExponentPushToken[...]", "title": "...", "body": "...", "data": {...} }

# Simulate rate limiting state
# For a more stateful rate limit simulation across multiple separate calls to this script:
# 1. Read current request count and timestamp from RATE_LIMIT_STATE_FILE.
# 2. If limit exceeded, return 429.
# 3. Otherwise, increment count, update timestamp, write back to file.
# This mock will use a simpler probabilistic rate limit or one controlled by env var for now.
# MOCK_RATE_LIMIT_HIT_CHANCE (0-100)
# MOCK_FORCE_RATE_LIMIT_ERROR (true/false)

handle_batch() {
    local request_body
    request_body=$(cat) # Read the JSON batch from stdin

    log_api "Received batch request: $request_body"
    check_auth # Simple auth check

    # Simulate forced server error
    if [ "$MOCK_FORCE_SERVER_ERROR" == "true" ]; then
        log_api "Simulating forced server error (500)."
        echo '{
            "errors": [{
                "code": "INTERNAL_SERVER_ERROR",
                "message": "A simulated internal server error occurred."
            }]
        }'
        exit 500 # Internal Server Error
    fi

    # Simulate rate limit exceeded
    if [ "$MOCK_FORCE_RATE_LIMIT_ERROR" == "true" ]; then
        log_api "Simulating forced rate limit error (429)."
        echo '{
            "errors": [{
                "code": "RATE_LIMIT_ERROR",
                "message": "Simulated rate limit exceeded. Try again later."
            }]
        }'
        exit 429 # Too Many Requests
    fi
    if [ -n "$MOCK_RATE_LIMIT_HIT_CHANCE" ] && [ "$(shuf -i 1-100 -n 1)" -le "$MOCK_RATE_LIMIT_HIT_CHANCE" ]; then
        log_api "Simulating probabilistic rate limit error (429)."
         echo '{
            "errors": [{
                "code": "RATE_LIMIT_ERROR",
                "message": "Probabilistic simulated rate limit exceeded."
            }]
        }'
        exit 429
    fi


    local batch_response_data=() # Array to hold individual ticket objects
    local has_errors=false

    # Process each notification in the batch
    # Use jq to parse the array of notifications
    echo "$request_body" | jq -c '.[]' | while IFS= read -r notification_json; do
        local token=$(echo "$notification_json" | jq -r '.to')
        local ticket_id="ticket-$(date +%s%N)-${RANDOM}"
        local status="ok"
        local message=""
        local details_code="" # e.g., DeviceNotRegistered

        # Simulate specific errors based on token content or other conditions
        if [[ "$token" == *INVALID_TOKEN_FORMAT* ]]; then
            status="error"
            message="Invalid push token format."
            details_code="InvalidCredentials" # Expo uses this for bad token format
            has_errors=true
        elif [[ "$token" == *DeviceNotRegisteredRecipient* ]] || [[ "$token" == *json_DeviceNotRegistered* ]]; then
            status="error"
            message="Device not registered for push notifications."
            details_code="DeviceNotRegistered"
            has_errors=true
        elif [[ "$token" == *MessageTooBigRecipient* ]]; then
            # Check body/title length if needed, or just use the token cue
            local body_len=$(echo "$notification_json" | jq -r '.body // "" | length')
            if [ "$body_len" -gt 200 ]; then # Arbitrary limit for mock
                status="error"
                message="Notification message payload was too large."
                details_code="MessageTooBig"
                has_errors=true
            fi
        elif [[ "$token" == *MessageRateExceeded* ]] || [[ "$token" == *json_MessageRateExceeded* ]]; then
            # This error is usually per device, not per batch, but can be simulated
            status="error"
            message="Message rate exceeded for this device." # This specific message is not typical from Expo for single msg
            details_code="MessageRateExceeded" # This is a real Expo error type
            has_errors=true
        elif [ -z "$token" ] || [ "$token" == "null" ]; then
             status="error"
             message="Push token is missing or null."
             details_code="InvalidCredentials"
             has_errors=true
        fi

        # Simulate random individual failures not cued by token
        if [ "$status" == "ok" ] && [ -n "$MOCK_INDIVIDUAL_FAIL_RATE" ] && \
           [ "$(shuf -i 1-100 -n 1)" -le "$MOCK_INDIVIDUAL_FAIL_RATE" ]; then
            status="error"
            message="A random simulated error occurred for this token."
            details_code="PUSH_TOO_MANY_EXPERIENCE_IDS" # Example of a less common error
            has_errors=true
        fi

        # Construct ticket response for this notification
        if [ "$status" == "ok" ]; then
            batch_response_data+=("$(jq -n --arg id "$ticket_id" --arg status "$status" \
                '{id: $id, status: $status}')")
        else
            batch_response_data+=("$(jq -n --arg id "$ticket_id" --arg status "$status" --arg msg "$message" --arg code "$details_code" \
                '{id: $id, status: $status, message: $msg, details: {error: $code}}')")
        fi
    done

    # Join individual ticket responses into a JSON array
    local final_response_json_data=$(printf "%s," "${batch_response_data[@]}")
    final_response_json_data="[${final_response_json_data%,}]" # Remove trailing comma and wrap in array

    log_api "Batch processed. Has errors: $has_errors. Response data: $final_response_json_data"

    # Construct the final response object
    # Expo API returns HTTP 200 even if there are individual errors in the batch.
    # Errors array at the top level is for API-level errors (auth, rate limit, server error).
    echo "{\"data\": $final_response_json_data}"
    exit 0 # HTTP OK
}


# --- Main ---
log_api "Mock Expo API script started."

# Check if input is piped
if [ -p /dev/stdin ]; then
    handle_batch
else
    log_api "No input piped to mock_expo_api.sh. Expecting JSON batch via stdin."
    echo '{
        "errors": [{
            "code": "VALIDATION_ERROR",
            "message": "Request body should be a JSON array of push notification objects."
        }]
    }'
    exit 400 # Bad Request
fi

log_api "Mock Expo API script finished."
exit 0 # Should be unreachable due to exits in handle_batch or above error
