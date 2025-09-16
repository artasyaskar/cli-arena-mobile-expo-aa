#!/bin/bash

# Mock Authentication API for cli-session-timeout-manager task
# Simulates /login and /refresh endpoints.

LOG_FILE="mock_auth_api.log"
# Simple in-memory store for refresh tokens and their validity/associated user.
# For a real app, this would be a database.
# Format: refresh_token_value|user_id|expiry_timestamp_utc_seconds|is_valid(true/false)
# For this mock, we'll just track issued refresh tokens.
# Let's use a temporary file for this mock server instance.
MOCK_REFRESH_TOKEN_DB="${MOCK_AUTH_REFRESH_DB:-./mock_refresh_tokens.db}"

# Lifespans (in seconds)
ACCESS_TOKEN_LIFESPAN_SECONDS=${MOCK_ACCESS_TOKEN_LIFESPAN:-60} # Default 1 minute
REFRESH_TOKEN_LIFESPAN_SECONDS=${MOCK_REFRESH_TOKEN_LIFESPAN:-300} # Default 5 minutes

# Mock user credentials
VALID_USERNAME="testuser"
VALID_PASSWORD="password123"

log_auth_api() {
    echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MOCK_AUTH_API] $1" >> "$LOG_FILE"
}

# Ensure refresh token DB file exists
touch "$MOCK_REFRESH_TOKEN_DB"

# $1: user_id
# $2: lifespan_seconds
generate_token() {
    local user_id="$1"
    local lifespan="$2"
    local type_prefix="$3" # "at_" or "rt_"
    local expiry_timestamp=$(( $(date +%s) + lifespan ))
    # Simple token: prefix_userid_random_expiry
    local token_value="${type_prefix}${user_id}_$(LC_ALL=C head /dev/urandom | LC_ALL=C tr -dc A-Za-z0-9 | head -c 10)_${expiry_timestamp}"
    echo "$token_value"
}

# Endpoint: /login
# Input (form-encoded or JSON): username, password
# Output: JSON { access_token, access_token_expires_at, refresh_token, refresh_token_expires_at }
handle_login() {
    local username password
    # Simplistic parsing: assume 'username=X&password=Y' or JSON in request body
    # For testing, we'll read from env vars set by the test or solution script.
    # Or, if piped, try to parse.
    if [ -p /dev/stdin ]; then
        local body=$(cat)
        if echo "$body" | jq -e . >/dev/null 2>&1; then # JSON body
            username=$(echo "$body" | jq -r '.username')
            password=$(echo "$body" | jq -r '.password')
        else # Assume form-encoded
            username=$(echo "$body" | sed -n 's/.*username=\([^&]*\).*/\1/p')
            password=$(echo "$body" | sed -n 's/.*password=\([^&]*\).*/\1/p')
        fi
    else # Fallback to env vars if not piped (for simpler test calls)
        username="$REQ_USERNAME"
        password="$REQ_PASSWORD"
    fi

    log_auth_api "Login attempt for user: $username"

    if [ "$username" == "$VALID_USERNAME" ] && [ "$password" == "$VALID_PASSWORD" ]; then
        local user_id="user_${username}" # Internal user ID
        local access_token=$(generate_token "$user_id" "$ACCESS_TOKEN_LIFESPAN_SECONDS" "at_")
        local refresh_token=$(generate_token "$user_id" "$REFRESH_TOKEN_LIFESPAN_SECONDS" "rt_")

        local at_expiry_ts=$(( $(date +%s) + ACCESS_TOKEN_LIFESPAN_SECONDS ))
        local rt_expiry_ts=$(( $(date +%s) + REFRESH_TOKEN_LIFESPAN_SECONDS ))

        # Store refresh token (very basic)
        echo "$refresh_token|$user_id|$rt_expiry_ts|true" >> "$MOCK_REFRESH_TOKEN_DB"
        log_auth_api "User '$username' logged in. AT expires at $at_expiry_ts, RT expires at $rt_expiry_ts."

        echo "$(jq -n \
            --arg at "$access_token" \
            --arg rt "$refresh_token" \
            --arg ate "$at_expiry_ts" \
            --arg rte "$rt_expiry_ts" \
            '{access_token: $at, access_token_expires_at: ($ate|tonumber), refresh_token: $rt, refresh_token_expires_at: ($rte|tonumber), status: "success"}')"
        return 0 # HTTP OK
    else
        log_auth_api "Login failed for user: $username. Invalid credentials."
        echo '{"error": "invalid_credentials", "error_description": "Username or password incorrect."}'
        return 401 # Unauthorized
    fi
}

# Endpoint: /refresh
# Input: refresh_token
# Output: JSON { access_token, access_token_expires_at, (optionally new) refresh_token, refresh_token_expires_at }
handle_refresh() {
    local client_refresh_token
    if [ -p /dev/stdin ]; then
        local body=$(cat)
        client_refresh_token=$(echo "$body" | jq -r '.refresh_token // ""')
    else
         client_refresh_token="$REQ_REFRESH_TOKEN"
    fi

    log_auth_api "Refresh attempt with token: $client_refresh_token"

    if [ -z "$client_refresh_token" ]; then
        log_auth_api "Refresh failed: No refresh token provided."
        echo '{"error": "invalid_request", "error_description": "Refresh token is missing."}'
        return 400 # Bad Request
    fi

    local token_record=$(grep "^${client_refresh_token}|" "$MOCK_REFRESH_TOKEN_DB")
    if [ -z "$token_record" ]; then
        log_auth_api "Refresh failed: Refresh token not found or invalid."
        echo '{"error": "invalid_grant", "error_description": "Refresh token is invalid or expired."}'
        return 401 # Unauthorized (or 400 Bad Request depending on RFC for OAuth)
    fi

    IFS='|' read -r stored_token user_id expiry_ts is_valid_str <<< "$token_record"

    local current_ts=$(date +%s)
    if [ "$is_valid_str" != "true" ] || [ "$current_ts" -gt "$expiry_ts" ]; then
        log_auth_api "Refresh failed: Token '$client_refresh_token' for user '$user_id' is marked invalid or expired (Expiry: $expiry_ts, Now: $current_ts)."
        # Invalidate this token in DB if it was just found to be expired by time check
        sed -i.bak "s|^${stored_token}|.*|false$|${stored_token}|${user_id}|${expiry_ts}|false|" "$MOCK_REFRESH_TOKEN_DB" && rm -f "$MOCK_REFRESH_TOKEN_DB.bak"
        echo '{"error": "invalid_grant", "error_description": "Refresh token is invalid or expired."}'
        return 401
    fi

    # Successfully validated refresh token. Issue new tokens.
    # Option: Invalidate old refresh token (one-time use)
    local invalidate_old_rt_on_refresh="${MOCK_INVALIDATE_OLD_RT_ON_REFRESH:-true}"
    if [ "$invalidate_old_rt_on_refresh" == "true" ]; then
        sed -i.bak "s|^${stored_token}|.*|false$|${stored_token}|${user_id}|${expiry_ts}|false|" "$MOCK_REFRESH_TOKEN_DB" && rm -f "$MOCK_REFRESH_TOKEN_DB.bak"
        log_auth_api "Invalidated old refresh token: $stored_token"
    fi

    local new_access_token=$(generate_token "$user_id" "$ACCESS_TOKEN_LIFESPAN_SECONDS" "at_")
    local new_refresh_token # Optionally issue a new refresh token
    local new_rt_expiry_ts

    local rotate_refresh_token="${MOCK_ROTATE_REFRESH_TOKEN:-true}"
    if [ "$rotate_refresh_token" == "true" ]; then
        new_refresh_token=$(generate_token "$user_id" "$REFRESH_TOKEN_LIFESPAN_SECONDS" "rt_")
        new_rt_expiry_ts=$(( $(date +%s) + REFRESH_TOKEN_LIFESPAN_SECONDS ))
        echo "$new_refresh_token|$user_id|$new_rt_expiry_ts|true" >> "$MOCK_REFRESH_TOKEN_DB"
    else
        new_refresh_token="$stored_token" # Re-use existing refresh token
        new_rt_expiry_ts="$expiry_ts"     # Its expiry doesn't change
    fi

    local new_at_expiry_ts=$(( $(date +%s) + ACCESS_TOKEN_LIFESPAN_SECONDS ))
    log_auth_api "Token refreshed for user '$user_id'. New AT expires $new_at_expiry_ts, New RT expires $new_rt_expiry_ts."

    echo "$(jq -n \
        --arg nat "$new_access_token" \
        --arg nrt "$new_refresh_token" \
        --arg nate "$new_at_expiry_ts" \
        --arg nrte "$new_rt_expiry_ts" \
        '{access_token: $nat, access_token_expires_at: ($nate|tonumber), refresh_token: $nrt, refresh_token_expires_at: ($nrte|tonumber), status: "success"}')"
    return 0
}

# Endpoint: /validate (For testing - protected resource might do this implicitly)
# Input: access_token
# Output: { valid: true/false, user_id, expires_at }
handle_validate() {
    local client_access_token
     if [ -p /dev/stdin ]; then
        local body=$(cat)
        client_access_token=$(echo "$body" | jq -r '.access_token // ""')
    else
        client_access_token="$REQ_ACCESS_TOKEN"
    fi

    log_auth_api "Validate attempt for token: $client_access_token"
    echo "DEBUG: client_access_token = '$client_access_token'" >&2
    if [[ "$client_access_token" != at_* ]]; then # Basic check for our mock token format
        log_auth_api "Validate failed: Invalid token format."
        echo '{"valid": false, "error": "invalid_token", "error_description": "Invalid token format."}'
        return 401
    fi

    # Extract expiry from token (e.g., at_userid_random_TIMESTAMP)
    local token_expiry_ts=$(echo "$client_access_token" | awk -F'_' '{print $NF}')
    local user_id_from_token=$(echo "$client_access_token" | awk -F'_' '{print $2}')

    if ! [[ "$token_expiry_ts" =~ ^[0-9]+$ ]]; then
        log_auth_api "Validate failed: Could not parse expiry from token."
        echo '{"valid": false, "error": "invalid_token", "error_description": "Malformed token."}'
        return 401
    fi

    local current_ts=$(date +%s)
    if [ "$current_ts" -gt "$token_expiry_ts" ]; then
        log_auth_api "Validate failed: Token expired (Expiry: $token_expiry_ts, Now: $current_ts)."
        echo "$(jq -n --arg uid "$user_id_from_token" --argjson exp "$token_expiry_ts" \
            '{valid: false, user_id: $uid, expires_at: $exp, error: "token_expired", error_description: "Access token has expired."}')"
        return 401
    else
        log_auth_api "Validate success: Token valid for user '$user_id_from_token'."
         echo "$(jq -n --arg uid "$user_id_from_token" --argjson exp "$token_expiry_ts" \
            '{valid: true, user_id: $uid, expires_at: ($exp|tonumber)}')"
        return 0
    fi
}

# Endpoint: /logout (optional, to invalidate refresh token)
# Input: refresh_token
handle_logout() {
    local client_refresh_token
    if [ -p /dev/stdin ]; then
        local body=$(cat)
        client_refresh_token=$(echo "$body" | jq -r '.refresh_token // ""')
    else
         client_refresh_token="$REQ_REFRESH_TOKEN"
    fi

    log_auth_api "Logout attempt for refresh token: $client_refresh_token"
    if [ -z "$client_refresh_token" ]; then
        log_auth_api "Logout: No refresh token provided." # Not necessarily an error, client might just clear locally
        echo '{"status": "success", "message": "Local logout assumed."}'
        return 200
    fi

    local token_record=$(grep "^${client_refresh_token}|" "$MOCK_REFRESH_TOKEN_DB")
    if [ -n "$token_record" ]; then
        IFS='|' read -r stored_token user_id expiry_ts is_valid_str <<< "$token_record"
        sed -i.bak "s|^${stored_token}|.*|false$|${stored_token}|${user_id}|${expiry_ts}|false|" "$MOCK_REFRESH_TOKEN_DB" && rm -f "$MOCK_REFRESH_TOKEN_DB.bak"
        log_auth_api "Logout successful: Refresh token '$client_refresh_token' for user '$user_id' invalidated."
        echo '{"status": "success", "message": "Refresh token invalidated."}'
        return 200
    else
        log_auth_api "Logout: Refresh token '$client_refresh_token' not found. No action on server."
        echo '{"status": "success", "message": "Token not found, no action needed."}' # Idempotent logout
        return 200
    fi
}


# --- Main Request Router ---
# Expects endpoint as first argument, e.g. ./mock_auth_api.sh /login
# Input data for POSTs (login, refresh) can be via stdin or env vars for test simplicity.

if [ -z "$1" ]; then
    log_auth_api "No endpoint specified."
    echo "Usage: $0 /<endpoint> (e.g. /login, /refresh, /validate, /logout)" >&2
    exit 400
fi

ENDPOINT="$1"
HTTP_STATUS_CODE=200 # Default

case "$ENDPOINT" in
    /login)
        handle_login
        HTTP_STATUS_CODE=$?
        ;;
    /refresh)
        handle_refresh
        HTTP_STATUS_CODE=$?
        ;;
    /validate) # For testing token validity
        handle_validate
        HTTP_STATUS_CODE=$?
        ;;
    /logout)
        handle_logout
        HTTP_STATUS_CODE=$?
        ;;
    *)
        log_auth_api "Unknown endpoint: $ENDPOINT"
        echo "{\"error\": \"not_found\", \"error_description\": \"Endpoint $ENDPOINT not found.\"}"
        HTTP_STATUS_CODE=404
        ;;
esac

exit $HTTP_STATUS_CODE
