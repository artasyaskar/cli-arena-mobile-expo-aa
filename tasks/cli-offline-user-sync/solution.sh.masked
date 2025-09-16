#!/bin/bash

# solution.sh for cli-offline-user-sync

# --- Configuration ---
OFFLINE_QUEUE_FILE="offline_actions.json"
PROCESSED_ACTIONS_LOG="processed_actions.log"
MOCK_SERVER_URL="./resources/mock_server.sh" # Path to the mock server script
MAX_RETRIES=${MAX_RETRIES:-5}
INITIAL_BACKOFF_SECONDS=${INITIAL_BACKOFF_SECONDS:-1} # Initial delay for retry
CONFLICT_RESOLUTION_CREATE=${CONFLICT_RESOLUTION_CREATE:-"server-wins"} # server-wins, client-wins
CONFLICT_RESOLUTION_UPDATE=${CONFLICT_RESOLUTION_UPDATE:-"timestamp"} # server-wins, client-wins, timestamp
CONFLICT_RESOLUTION_DELETE=${CONFLICT_RESOLUTION_DELETE:-"force-delete"} # force-delete, timestamp (reject if server newer)

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq could not be found. Please install jq to run this script."
    exit 1
fi

# --- Logging ---
log_message() {
    echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [SOLUTION] $1"
}

# --- Action Queue Management ---
initialize_queue() {
    if [ ! -f "$OFFLINE_QUEUE_FILE" ]; then
        echo "[]" > "$OFFLINE_QUEUE_FILE"
        log_message "Initialized empty offline action queue: $OFFLINE_QUEUE_FILE"
    fi
    # Ensure processed actions log exists
    touch "$PROCESSED_ACTIONS_LOG"
}

# $1: type (CREATE, UPDATE, DELETE)
# $2: entity (e.g., users, posts)
# $3: id (for UPDATE, DELETE) or payload for CREATE (json string)
# $4: payload for UPDATE (json string)
add_action_to_queue() {
    local type="$1"
    local entity="$2"
    local id_or_payload="$3"
    local update_payload="$4"
    local action_id="action_$(date +%s%N)_${RANDOM}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ") # UTC timestamp

    local action_json

    case "$type" in
        CREATE)
            # id_or_payload is the actual payload here
            action_json=$(jq -n \
                --arg actionId "$action_id" \
                --arg type "$type" \
                --arg entity "$entity" \
                --argjson payload "$id_or_payload" \
                --arg timestamp "$timestamp" \
                '{actionId: $actionId, type: $type, entity: $entity, payload: $payload, timestamp: $timestamp, client_version: 1}')
            ;;
        UPDATE)
            action_json=$(jq -n \
                --arg actionId "$action_id" \
                --arg type "$type" \
                --arg entity "$entity" \
                --arg id "$id_or_payload" \
                --argjson payload "$update_payload" \
                --arg timestamp "$timestamp" \
                '{actionId: $actionId, type: $type, entity: $entity, id: $id, payload: $payload, timestamp: $timestamp, client_version: 1}') # client_version might need to be fetched
            ;;
        DELETE)
            action_json=$(jq -n \
                --arg actionId "$action_id" \
                --arg type "$type" \
                --arg entity "$entity" \
                --arg id "$id_or_payload" \
                --arg timestamp "$timestamp" \
                '{actionId: $actionId, type: $type, entity: $entity, id: $id, timestamp: $timestamp, client_version: 1}') # client_version might need to be fetched
            ;;
        *)
            log_message "ERROR: Invalid action type '$type'"
            return 1
            ;;
    esac

    # Validate action (basic validation)
    if ! echo "$action_json" | jq -e . > /dev/null 2>&1; then
        log_message "ERROR: Generated action JSON is invalid: $action_json"
        return 1
    fi

    # Add to queue
    local current_queue=$(cat "$OFFLINE_QUEUE_FILE")
    echo "$current_queue" | jq --argjson action "$action_json" '. + [$action]' > "$OFFLINE_QUEUE_FILE.tmp" && mv "$OFFLINE_QUEUE_FILE.tmp" "$OFFLINE_QUEUE_FILE"
    log_message "Added action $action_id to queue: $type $entity"
    echo "Action $action_id added."
}

# --- Sync Logic ---
# $1: action_json
# $2: retry_count
# $3: max_retries
# $4: backoff
process_action() {
    local action_json="$1"
    local retry_count="$2"
    local max_retries="$3"
    local backoff="$4"

    local action_id=$(echo "$action_json" | jq -r '.actionId')
    local action_type=$(echo "$action_json" | jq -r '.type')
    local entity=$(echo "$action_json" | jq -r '.entity')
    local id=$(echo "$action_json" | jq -r '.id // ""') # For UPDATE/DELETE
    local payload=$(echo "$action_json" | jq -c '.payload // {}') # For CREATE/UPDATE
    local client_timestamp=$(echo "$action_json" | jq -r '.timestamp')

    # Check if action was already processed
    if grep -q "^$action_id$" "$PROCESSED_ACTIONS_LOG"; then
        log_message "Action $action_id already processed. Skipping."
        return 0 # Success, already done
    fi

    log_message "Processing action $action_id: $action_type $entity $id (Attempt: $((retry_count + 1)))"

    # Prepare request for mock server
    local request_body
    local conflict_resolution_strategy=""

    case "$action_type" in
        CREATE)
            conflict_resolution_strategy=$CONFLICT_RESOLUTION_CREATE
            request_body=$(jq -n \
                --arg type "$action_type" \
                --arg entity "$entity" \
                --argjson payload "$payload" \
                --arg timestamp "$client_timestamp" \
                --arg conflict_resolution "$conflict_resolution_strategy" \
                '{type: $type, entity: $entity, payload: $payload, timestamp: $timestamp, conflict_resolution: $conflict_resolution}')
            ;;
        UPDATE)
            conflict_resolution_strategy=$CONFLICT_RESOLUTION_UPDATE
            request_body=$(jq -n \
                --arg type "$action_type" \
                --arg entity "$entity" \
                --arg id "$id" \
                --argjson payload "$payload" \
                --arg timestamp "$client_timestamp" \
                --arg conflict_resolution "$conflict_resolution_strategy" \
                '{type: $type, entity: $entity, id: $id, payload: $payload, timestamp: $timestamp, conflict_resolution: $conflict_resolution}')
            ;;
        DELETE)
            conflict_resolution_strategy=$CONFLICT_RESOLUTION_DELETE
             request_body=$(jq -n \
                --arg type "$action_type" \
                --arg entity "$entity" \
                --arg id "$id" \
                --arg timestamp "$client_timestamp" \
                --arg conflict_resolution "$conflict_resolution_strategy" \
                '{type: $type, entity: $entity, id: $id, timestamp: $timestamp, conflict_resolution: $conflict_resolution}')
            ;;
    esac

    # Simulate API call
    local response
    response=$(echo "$request_body" | MOCK_DB_PATH="${MOCK_DB_PATH}" SIMULATE_LATENCY="${SIMULATE_LATENCY}" FAIL_RATE="${FAIL_RATE}" "$MOCK_SERVER_URL" 2>/dev/null)
    local http_status_code=$? # mock_server.sh returns HTTP status codes

    if [ -z "$response" ]; then # Handle case where mock_server.sh produces no output (e.g. script error)
        log_message "ERROR: No response from mock server for action $action_id."
        response='{"status":"error", "message":"No response from server"}'
        http_status_code=500 # Generic server error
    fi

    local response_status=$(echo "$response" | jq -r '.status')

    log_message "Response for $action_id: HTTP $http_status_code, Status $response_status, Body: $(echo "$response" | jq -c .)"

    if [ "$response_status" == "success" ]; then
        log_message "Action $action_id processed successfully. Operation: $(echo "$response" | jq -r '.operation // "N/A"')"
        echo "$action_id" >> "$PROCESSED_ACTIONS_LOG" # Mark as processed
        return 0 # Success
    elif [ "$response_status" == "conflict" ]; then
        log_message "CONFLICT for action $action_id: $(echo "$response" | jq -r '.message'). Resolution strategy: $conflict_resolution_strategy. Server data: $(echo "$response" | jq -c '.server_item // .existing_item // {}')"
        # Depending on strategy for conflict (e.g. if client-wins was attempted and failed, or if strategy is server-wins),
        # we might mark it as "processed" (as in, conflict handled, nothing more to do from client side)
        # For this example, conflicts that are not client-wins are considered "terminal" for this action from client perspective
        echo "$action_id" >> "$PROCESSED_ACTIONS_LOG" # Mark as processed (conflict handled)
        return 0 # Success (in terms of processing the action, even if it was a server-wins conflict)
    else # Error or retryable failure
        log_message "FAILED action $action_id: $(echo "$response" | jq -r '.message // "Unknown error"')"
        if [ "$retry_count" -lt "$max_retries" ]; then
            local jitter=$(awk -v b="$backoff" 'BEGIN{srand(); print b * (0.8 + rand() * 0.4)}') # +/- 20% jitter
            log_message "Retrying action $action_id in ${jitter}s... (Retry $((retry_count + 1))/$max_retries)"
            sleep "$jitter"
            local next_backoff=$(echo "$backoff * 2" | bc)
            # Cap backoff to avoid excessively long waits, e.g., 60 seconds
            if (( $(echo "$next_backoff > 60" | bc -l) )); then next_backoff=60; fi
            process_action "$action_json" "$((retry_count + 1))" "$max_retries" "$next_backoff"
            return $? # Propagate exit code from retry
        else
            log_message "Max retries reached for action $action_id. Action failed permanently."
            return 1 # Failure
        fi
    fi
}

sync_offline_actions() {
    log_message "Starting sync process..."
    if [ ! -s "$OFFLINE_QUEUE_FILE" ] || [ "$(cat "$OFFLINE_QUEUE_FILE")" == "[]" ]; then
        log_message "Offline queue is empty. Nothing to sync."
        echo "Offline queue is empty."
        return 0
    fi

    local actions_to_process=$(cat "$OFFLINE_QUEUE_FILE")
    local temp_queue_file="$OFFLINE_QUEUE_FILE.syncing"
    mv "$OFFLINE_QUEUE_FILE" "$temp_queue_file" # Move to prevent new additions during sync
    echo "[]" > "$OFFLINE_QUEUE_FILE" # Initialize new empty queue

    local all_successful=true
    local failed_actions="[]"

    log_message "Processing $(echo "$actions_to_process" | jq '. | length') actions from $temp_queue_file"

    for row in $(echo "${actions_to_process}" | jq -r '.[] | @base64'); do
        _jq() {
            echo "${row}" | base64 --decode | jq -r "${1}"
        }
        local action_json=$(_jq '.') # Get the full JSON of the action

        if process_action "$action_json" 0 "$MAX_RETRIES" "$INITIAL_BACKOFF_SECONDS"; then
            log_message "Successfully processed or handled action $(_jq '.actionId')."
        else
            log_message "Failed to process action $(_jq '.actionId') after all retries."
            all_successful=false
            failed_actions=$(echo "$failed_actions" | jq --argjson action "$action_json" '. + [$action]')
        fi
    done

    # Handle failed actions: re-queue them or move to a dead-letter queue
    if [ "$(echo "$failed_actions" | jq '. | length')" -gt 0 ]; then
        log_message "Re-queueing $(echo "$failed_actions" | jq '. | length') failed actions."
        local current_queue_content=$(cat "$OFFLINE_QUEUE_FILE")
        # Prepend failed actions to the current queue to be retried next time
        echo "$failed_actions" | jq --argjson existing_queue "$current_queue_content" '. + $existing_queue' > "$OFFLINE_QUEUE_FILE.tmp" && mv "$OFFLINE_QUEUE_FILE.tmp" "$OFFLINE_QUEUE_FILE"
        echo "Some actions failed and were re-queued. Check logs."
    fi

    rm "$temp_queue_file" # Clean up the temporary file

    if $all_successful; then
        log_message "Sync process completed successfully."
        echo "Sync process completed."
        return 0
    else
        log_message "Sync process completed with some failures."
        return 1
    fi
}


# --- CLI Commands ---
COMMAND="$1"
shift

case "$COMMAND" in
    add)
        # Usage: ./solution.sh add <type> <entity> <id_or_payload_for_create> [payload_for_update]
        # e.g., ./solution.sh add CREATE users '{"id":"user_new","name":"New User"}'
        # e.g., ./solution.sh add UPDATE users "user_1" '{"email":"new.email@example.com"}'
        # e.g., ./solution.sh add DELETE posts "post_1"
        if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 add <TYPE> <ENTITY> <ID_OR_CREATE_PAYLOAD> [UPDATE_PAYLOAD]"
            echo "TYPE: CREATE, UPDATE, DELETE"
            echo "ENTITY: e.g., users, posts"
            echo "ID_OR_CREATE_PAYLOAD: Record ID for UPDATE/DELETE, or JSON string for CREATE payload"
            echo "UPDATE_PAYLOAD: JSON string for UPDATE payload (only for UPDATE type)"
            exit 1
        fi
        type="$1"
        entity="$2"
        id_or_payload="$3"
        update_payload="$4" # Will be empty if not UPDATE

        initialize_queue
        add_action_to_queue "$type" "$entity" "$id_or_payload" "$update_payload"
        ;;
    sync)
        # Usage: ./solution.sh sync
        initialize_queue
        sync_offline_actions
        ;;
    queue)
        # Usage: ./solution.sh queue
        initialize_queue
        echo "Current Offline Action Queue ($OFFLINE_QUEUE_FILE):"
        jq '.' "$OFFLINE_QUEUE_FILE"
        ;;
    clear_queue)
        initialize_queue
        echo "[]" > "$OFFLINE_QUEUE_FILE"
        echo "" > "$PROCESSED_ACTIONS_LOG" # Also clear processed log for a full reset
        log_message "Offline queue and processed log cleared."
        echo "Offline queue and processed log cleared."
        ;;
    get_mock_db)
        # Usage: ./solution.sh get_mock_db
        cat "${MOCK_DB_PATH:-./resources/mock_supabase_db.json}" | jq '.'
        ;;
    reset_mock_db)
        # Usage: ./solution.sh reset_mock_db [template_file_path]
        # Default template is resources/mock_supabase_db.json from task structure
        local template_path="${1:-resources/mock_supabase_db.json}"
        if [ -f "$template_path" ]; then
            cp "$template_path" "${MOCK_DB_PATH:-./resources/mock_supabase_db.json}"
            log_message "Mock DB has been reset from $template_path."
            echo "Mock DB has been reset from $template_path."
        else
            log_message "ERROR: Template DB file $template_path not found."
            echo "ERROR: Template DB file $template_path not found."
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 <COMMAND>"
        echo "Commands:"
        echo "  add <TYPE> <ENTITY> <ID_OR_CREATE_PAYLOAD> [UPDATE_PAYLOAD] - Add an action to the offline queue."
        echo "                                                              Example CREATE: $0 add CREATE users '{\"id\":\"user_new\",\"name\":\"New User\"}'"
        echo "                                                              Example UPDATE: $0 add UPDATE users \"user_1\" '{\"email\":\"new.email@example.com\"}'"
        echo "                                                              Example DELETE: $0 add DELETE posts \"post_1\""
        echo "  sync                 - Process actions from the queue and sync with the (mock) server."
        echo "  queue                - Display the current offline action queue."
        echo "  clear_queue          - Clears the offline action queue and processed log."
        echo "  get_mock_db          - Displays the current state of the mock database."
        echo "  reset_mock_db [path] - Resets the mock database from a template (default: resources/mock_supabase_db.json)."
        exit 1
        ;;
esac

exit $?
