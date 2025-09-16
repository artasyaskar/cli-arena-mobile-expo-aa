#!/bin/bash

# mock_auth_server_multi_tenant.sh
# Simulates a multi-tenant authentication server.

USER_DATA_FILE="${USER_TENANT_ROLE_MAPPINGS_FILE:-./resources/user_tenant_role_mappings.json}"
LOG_FILE="mock_auth_server.log"

log_auth() {
    echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MOCK_AUTH_SERVER] $1" >> "$LOG_FILE"
}

# Ensure user data file exists
if [ ! -f "$USER_DATA_FILE" ]; then
    log_auth "ERROR: User data file '$USER_DATA_FILE' not found."
    echo '{"error": "server_configuration_error", "message": "User data file missing."}'
    exit 500
fi

# Endpoint: /login
# Input (JSON): {"username": "user", "password": "password"}
# Output: JSON { "primary_token": "...", "tenants": [ { "id": "...", "name": "...", "role": "..." } ], "status": "success" }
#      or JSON { "error": "...", "message": "..." }
handle_login() {
    local request_body
    request_body=$(cat) # Read JSON from stdin

    local username=$(echo "$request_body" | jq -r '.username')
    local password=$(echo "$request_body" | jq -r '.password')

    log_auth "Login attempt for username: '$username'"

    if [ -z "$username" ] || [ -z "$password" ]; then
        log_auth "Login failed: Username or password not provided."
        echo '{"error": "invalid_request", "message": "Username and password are required."}'
        return 400
    fi

    # Check credentials against USER_DATA_FILE
    local user_entry=$(jq -r --arg u "$username" '.users[$u]' "$USER_DATA_FILE")

    if [ "$user_entry" == "null" ] || [ -z "$user_entry" ]; then
        log_auth "Login failed: User '$username' not found."
        echo '{"error": "invalid_credentials", "message": "User not found."}'
        return 401
    fi

    local stored_password=$(echo "$user_entry" | jq -r '.password')
    if [ "$password" != "$stored_password" ]; then
        log_auth "Login failed: Incorrect password for user '$username'."
        echo '{"error": "invalid_credentials", "message": "Incorrect password."}'
        return 401
    fi

    # Credentials are valid, generate primary token and list tenants
    local primary_token="primary_token_for_${username}_$(date +%s%N)"
    local tenants_json=$(echo "$user_entry" | jq -r '.tenants | if . == null then [] else to_entries | map({id: .key, name: .value.name, role: .value.role}) end')

    log_auth "Login successful for user '$username'. Primary token generated. Tenants: $tenants_json"
    echo "$(jq -n --arg token "$primary_token" --argjson tenants "$tenants_json" \
        '{primary_token: $token, tenants: $tenants, status: "success"}')"
    return 0
}

# Endpoint: /tenant-token (Optional, can be used if tenant-specific tokens are needed)
# Input (JSON): {"primary_token": "...", "tenant_id": "..."}
# Output: JSON { "tenant_access_token": "...", "expires_at": "...", "status": "success" }
# For this mock, we will assume the primary_token itself is used with tenant context,
# so this endpoint might not be strictly necessary for the CLI's operation as designed.
# However, we can implement a basic version.
handle_tenant_token() {
    local request_body
    request_body=$(cat)

    local primary_token=$(echo "$request_body" | jq -r '.primary_token')
    local tenant_id=$(echo "$request_body" | jq -r '.tenant_id')

    log_auth "Tenant token request for tenant '$tenant_id' with primary token '$primary_token'"

    # Basic validation of primary_token (e.g., check prefix)
    if [[ "$primary_token" != primary_token_for_* ]]; then
        log_auth "Invalid primary token format."
        echo '{"error": "invalid_token", "message": "Invalid primary token."}'
        return 401
    fi

    local username=$(echo "$primary_token" | sed -E 's/primary_token_for_([^ _]+)_.*/\1/')

    # Check if user has access to this tenant (from USER_DATA_FILE)
    local user_tenant_role=$(jq -r --arg u "$username" --arg tid "$tenant_id" '.users[$u].tenants[$tid].role // "null"' "$USER_DATA_FILE")

    if [ "$user_tenant_role" == "null" ]; then
        log_auth "User '$username' does not have access to tenant '$tenant_id'."
        echo '{"error": "access_denied", "message": "User not authorized for this tenant."}'
        return 403
    fi

    local tenant_access_token="tenant_token_for_${username}_${tenant_id}_$(date +%s%N)"
    local expires_at=$(( $(date +%s) + 3600 )) # Expires in 1 hour

    log_auth "Tenant token generated for user '$username', tenant '$tenant_id'."
    echo "$(jq -n --arg tat "$tenant_access_token" --argjson exp "$expires_at" \
        '{tenant_access_token: $tat, expires_at: $exp, status: "success"}')"
    return 0
}


# --- Main Request Router ---
ENDPOINT="$1"
log_auth "Request received for endpoint: $ENDPOINT"

case "$ENDPOINT" in
    /login)
        handle_login
        exit $?
        ;;
    /tenant-token)
        handle_tenant_token
        exit $?
        ;;
    /get-role-permissions) # Helper for tests or CLI to fetch permissions
        # Input: {"role": "admin"}
        local request_body=$(cat)
        local role_name=$(echo "$request_body" | jq -r '.role')
        local permissions=$(jq -r --arg role "$role_name" '.roles_permissions[$role]' "$USER_DATA_FILE")
        if [ "$permissions" == "null" ]; then
            echo "{\"error\": \"not_found\", \"message\": \"Role '$role_name' not found.\"}"
            exit 404
        else
            echo "$(jq -n --argjson perms "$permissions" '{role: "'"$role_name"'", permissions: $perms}')"
            exit 0
        fi
        ;;
    *)
        log_auth "Unknown endpoint: $ENDPOINT"
        echo "{\"error\": \"not_found\", \"message\": \"Endpoint $ENDPOINT not found on mock auth server.\"}"
        exit 404
        ;;
esac
