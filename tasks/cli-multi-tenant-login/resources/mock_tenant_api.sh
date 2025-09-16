#!/bin/bash

# mock_tenant_api.sh
# Simulates a tenant-specific API endpoint that requires authentication and checks roles.

USER_DATA_FILE="${USER_TENANT_ROLE_MAPPINGS_FILE:-./resources/user_tenant_role_mappings.json}"
LOG_FILE="mock_tenant_api.log"

log_api() {
    echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MOCK_TENANT_API] $1" >> "$LOG_FILE"
}

# Expected headers or payload fields for context:
# - Authorization: Bearer <primary_token_or_tenant_token>
# - X-Tenant-ID: <tenant_id>
# - X-User-Role: <role_in_tenant> (optional, could be derived from token by API)

# $1: Required permission string (e.g., "view_items", "create_item")
# $2: User's role string (e.g., "admin", "member", "viewer")
# $3: Tenant ID (for logging/context, not directly used for permission check here as role is tenant-specific)
check_permission() {
    local required_permission="$1"
    local user_role="$2"
    local tenant_id="$3"

    log_api "Checking permission: User role '$user_role' needs '$required_permission' for tenant '$tenant_id'."

    if [ -z "$user_role" ]; then
        log_api "Permission check failed: No role provided."
        return 1 # Fail if no role
    fi

    # Fetch permissions for the role from USER_DATA_FILE
    local role_permissions=$(jq -r --arg role "$user_role" '.roles_permissions[$role] // "null"' "$USER_DATA_FILE")

    if [ "$role_permissions" == "null" ]; then
        log_api "Permission check failed: Role '$user_role' not found in permissions mapping."
        return 1 # Role not defined
    fi

    # Check if the required permission is in the list of permissions for that role
    if echo "$role_permissions" | jq -e --arg perm "$required_permission" '.[] | select(. == $perm)' > /dev/null; then
        log_api "Permission GRANTED for role '$user_role' to '$required_permission'."
        return 0 # Permission granted
    else
        log_api "Permission DENIED for role '$user_role' to '$required_permission'."
        return 1 # Permission denied
    fi
}


# --- Request Handling ---
# Endpoint: /<tenant_id>/items (GET, POST)
# Endpoint: /<tenant_id>/settings (GET, PUT)
# Endpoint: /<tenant_id>/admin/action (POST)

# Assumes HTTP_METHOD, REQUEST_URI, HTTP_AUTHORIZATION, HTTP_X_TENANT_ID, HTTP_X_USER_ROLE are set by curl/test harness.
# Example REQUEST_URI: /tenant_alpha/items

handle_request() {
    local method="$HTTP_METHOD"
    local uri_path="$REQUEST_URI" # e.g., /tenant_alpha/items
    local auth_header="$HTTP_AUTHORIZATION"
    local tenant_id_header="$HTTP_X_TENANT_ID" # This is the crucial context
    local user_role_header="$HTTP_X_USER_ROLE" # This might be derived from token server-side in reality

    log_api "Request: $method $uri_path, Tenant: $tenant_id_header, Role: $user_role_header, Auth: ${auth_header:0:20}..."

    # Basic Auth Check (presence and "Bearer" prefix)
    if [ -z "$auth_header" ] || [[ "$auth_header" != Bearer\ * ]]; then
        log_api "Auth failed: Missing or malformed Authorization header."
        echo '{"error": "Unauthorized", "message": "Authorization header missing or invalid."}'
        return 401
    fi
    local token="${auth_header#Bearer }" # Extract token

    # Token validation (very basic for mock: non-empty and starts with "primary_token_for_" or "tenant_token_for_")
    # A real API would validate this token with the auth server or by checking its signature/expiry.
    if [[ "$token" != primary_token_for_* && "$token" != tenant_token_for_* ]]; then
        log_api "Auth failed: Invalid token format '$token'."
        echo '{"error": "Unauthorized", "message": "Invalid token format."}'
        return 401
    fi

    # Extract username from token (assuming format "primary_token_for_USERNAME_...")
    local username
    if [[ "$token" == primary_token_for_* ]]; then
        username=$(echo "$token" | sed -E 's/primary_token_for_([^ _]+)_.*/\1/')
    elif [[ "$token" == tenant_token_for_* ]]; then
        username=$(echo "$token" | sed -E 's/tenant_token_for_([^ _]+)_.*/\1/')
    else
        username="unknown"
    fi
    log_api "Token appears valid for user '$username'."


    # Tenant ID check
    if [ -z "$tenant_id_header" ]; then
        log_api "Forbidden: Missing X-Tenant-ID header."
        echo '{"error": "Forbidden", "message": "X-Tenant-ID header is required."}'
        return 403
    fi

    # Role check
    if [ -z "$user_role_header" ]; then
        log_api "Forbidden: Missing X-User-Role header."
        echo '{"error": "Forbidden", "message": "X-User-Role header is required for this mock."}'
        return 403
    fi

    # Routing based on URI path and method
    # Example: /tenant_alpha/items
    local path_parts=($(echo "$uri_path" | tr '/' ' '))
    local request_tenant_id="${path_parts[1]}"
    local resource_type="${path_parts[2]}"
    local resource_action="${path_parts[3]}" # For things like /admin/action


    if [ "$request_tenant_id" != "$tenant_id_header" ]; then
        log_api "Forbidden: Tenant ID in URL ('$request_tenant_id') does not match X-Tenant-ID header ('$tenant_id_header')."
        echo '{"error": "Forbidden", "message": "Tenant ID mismatch between URL and header."}'
        return 403
    fi

    local required_permission=""
    local response_message=""

    case "$resource_type" in
        "items")
            if [ "$method" == "GET" ]; then
                required_permission="view_items"
                response_message="List of items for tenant $tenant_id_header."
            elif [ "$method" == "POST" ]; then
                required_permission="create_item"
                response_message="Item created in tenant $tenant_id_header."
            else
                echo '{"error": "Method Not Allowed"}'
                return 405
            fi
            ;;
        "settings")
            if [ "$method" == "GET" ] || [ "$method" == "PUT" ]; then # PUT could be create or update
                required_permission="view_settings" # Simplified: view_settings for both read/write
                if [ "$method" == "PUT" ]; then required_permission="admin_action"; fi # More specific for PUT
                response_message="Settings for tenant $tenant_id_header."
            else
                echo '{"error": "Method Not Allowed"}'
                return 405
            fi
            ;;
        "admin")
            if [ "$resource_action" == "action" ] && [ "$method" == "POST" ]; then
                required_permission="admin_action"
                response_message="Admin action performed in tenant $tenant_id_header."
            else
                echo '{"error": "Not Found"}'
                return 404
            fi
            ;;
        *)
            log_api "Resource type '$resource_type' not found."
            echo '{"error": "Not Found", "message": "Resource not found."}'
            return 404
            ;;
    esac

    # Check permission
    if ! check_permission "$required_permission" "$user_role_header" "$tenant_id_header"; then
        echo "$(jq -n --arg perm "$required_permission" --arg role "$user_role_header" \
            '{error: "Forbidden", message: ("User role '\''" + $role + "'\'' does not have permission '\''" + $perm + "'\'' for this operation.")}')"
        return 403
    fi

    # If all checks pass
    log_api "Access GRANTED to $method $uri_path for user '$username' with role '$user_role_header' in tenant '$tenant_id_header'."
    echo "$(jq -n --arg msg "$response_message" --arg user "$username" --arg role "$user_role_header" --arg tenant "$tenant_id_header" \
        '{status: "success", message: $msg, user: $user, role: $role, tenant: $tenant}')"
    return 0
}


# --- Main ---
log_api "Mock Tenant API script started. Method: $HTTP_METHOD, URI: $REQUEST_URI"

if [ -z "$HTTP_METHOD" ] || [ -z "$REQUEST_URI" ]; then
    log_api "HTTP_METHOD or REQUEST_URI not set. Cannot process request."
    echo '{"error": "Configuration Error", "message": "Server environment not set up for mock API."}'
    exit 500
fi

handle_request
exit $?
