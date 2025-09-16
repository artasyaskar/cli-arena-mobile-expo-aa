#!/bin/bash

# Mock Supabase Server
# Handles CRUD operations and simulates conflict scenarios for cli-offline-user-sync task.

DB_FILE="mock_supabase_db.json"
LOG_FILE="mock_server.log"
PERSISTED_DB_FILE_PATH="${MOCK_DB_PATH:-./mock_supabase_db.json}" # Allow override for testing

log() {
    echo "$(date +'%Y-%m-%dT%H:%M:%S%z'): $1" >> "$LOG_FILE"
}

# Initialize DB if it doesn't exist from template
if [ ! -f "$PERSISTED_DB_FILE_PATH" ] && [ -f "resources/mock_supabase_db.json" ]; then
    cp "resources/mock_supabase_db.json" "$PERSISTED_DB_FILE_PATH"
    log "Initialized mock database from template."
elif [ ! -f "$PERSISTED_DB_FILE_PATH" ]; then
    echo '{"users": [], "posts": []}' > "$PERSISTED_DB_FILE_PATH"
    log "Initialized empty mock database."
fi

# Simulate network delay and failures
SIMULATE_LATENCY=${SIMULATE_LATENCY:-0} # ms
FAIL_RATE=${FAIL_RATE:-0} # percentage, 0-100

# Read current database state
read_db() {
    cat "$PERSISTED_DB_FILE_PATH"
}

# Write to database state
write_db() {
    echo "$1" > "$PERSISTED_DB_FILE_PATH"
}

# Get current UTC timestamp in ISO 8601 format
current_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
}

# --- Request Handling ---
handle_request() {
    local request_body="$1"
    log "Received request: $request_body"

    # Simulate latency
    if [ "$SIMULATE_LATENCY" -gt 0 ]; then
        sleep "$(echo "$SIMULATE_LATENCY / 1000" | bc -l)"
    fi

    # Simulate random failure
    if [ "$FAIL_RATE" -gt 0 ] && [ "$(shuf -i 1-100 -n 1)" -le "$FAIL_RATE" ]; then
        log "Simulating network failure."
        echo '{"status": "error", "message": "Simulated network failure"}'
        return 503 # HTTP Service Unavailable
    fi

    local action_type=$(echo "$request_body" | jq -r '.type')
    local entity=$(echo "$request_body" | jq -r '.entity') # e.g., users, posts
    local id=$(echo "$request_body" | jq -r '.id')
    local payload=$(echo "$request_body" | jq -r '.payload')
    local client_timestamp=$(echo "$request_body" | jq -r '.timestamp') # Client's timestamp for the action
    # local client_version=$(echo "$request_body" | jq -r '.client_version') # Client's base version of the record for updates

    local db_content=$(read_db)
    local response

    case "$action_type" in
        "CREATE")
            local existing_item=$(echo "$db_content" | jq -r --arg entity "$entity" --arg id "$(echo "$payload" | jq -r .id)" '.[$entity][] | select(.id == $id)')
            if [ -n "$existing_item" ]; then
                # Conflict: item already exists
                log "CREATE Conflict: Item $entity with id $(echo "$payload" | jq -r .id) already exists."
                # For testing, we'll allow client to specify resolution or server defaults to server-wins
                local conflict_resolution_strategy=$(echo "$request_body" | jq -r '.conflict_resolution // "server-wins"')
                if [ "$conflict_resolution_strategy" == "client-wins" ];
                then
                    local new_item_payload=$(echo "$payload" | jq ".last_modified = \"$(current_timestamp)\" | .version = 1")
                    db_content=$(echo "$db_content" | jq --arg entity "$entity" --argjson newItem "$new_item_payload" --arg idToUpdate "$(echo "$payload" | jq -r .id)" \
                        '.[$entity] = ([.[$entity][] | select(.id != $idToUpdate)] + [$newItem])')
                    write_db "$db_content"
                    response='{"status": "success", "operation": "create_overwrite", "id": "'$(echo "$payload" | jq -r .id)'", "data": '$new_item_payload'}'
                    log "CREATE Conflict resolved with client-wins for $(echo "$payload" | jq -r .id)."
                else # server-wins
                    response='{"status": "conflict", "message": "Item already exists", "id": "'$(echo "$payload" | jq -r .id)'", "existing_item": '$existing_item'}'
                    log "CREATE Conflict, server-wins for $(echo "$payload" | jq -r .id)."
                fi
            else
                local new_item_id=$(echo "$payload" | jq -r .id)
                local new_item_payload=$(echo "$payload" | jq ".last_modified = \"$(current_timestamp)\" | .version = 1")
                db_content=$(echo "$db_content" | jq --arg entity "$entity" --argjson newItem "$new_item_payload" '.[$entity] += [$newItem]')
                write_db "$db_content"
                response='{"status": "success", "operation": "create", "id": "'$new_item_id'", "data": '$new_item_payload'}'
                log "CREATE success for $entity with id $new_item_id."
            fi
            ;;
        "UPDATE")
            local current_item=$(echo "$db_content" | jq -r --arg entity "$entity" --arg id "$id" '.[$entity][] | select(.id == $id)')
            if [ -z "$current_item" ]; then
                response='{"status": "error", "message": "Item not found for update", "id": "'$id'"}'
                log "UPDATE Error: Item $id not found in $entity."
            else
                local server_timestamp=$(echo "$current_item" | jq -r '.last_modified')
                # Conflict resolution strategy from client, defaulting to 'timestamp'
                local conflict_resolution=$(echo "$request_body" | jq -r '.conflict_resolution // "timestamp"')
                local client_wins=false

                if [ "$conflict_resolution" == "timestamp" ]; then
                    # Compare ISO8601 timestamps
                    if [[ "$client_timestamp" > "$server_timestamp" ]]; then
                        client_wins=true
                    fi
                elif [ "$conflict_resolution" == "client-wins" ]; then
                    client_wins=true
                fi # server-wins is the default if not client_wins

                if $client_wins ; then
                    local updated_item=$(echo "$current_item" | jq --argjson payload "$payload" '. + $payload')
                    updated_item=$(echo "$updated_item" | jq ".last_modified = \"$(current_timestamp)\" | .version += 1")
                    db_content=$(echo "$db_content" | jq --arg entity "$entity" --arg id "$id" --argjson updatedItem "$updated_item" \
                        '.[$entity] = ([.[$entity][] | select(.id != $id)] + [$updatedItem])')
                    write_db "$db_content"
                    response='{"status": "success", "operation": "update", "id": "'$id'", "data": '$updated_item'}'
                    log "UPDATE success for $id in $entity (Client Wins)."
                else # Server wins or client_timestamp is not greater
                    response='{"status": "conflict", "message": "Server version is newer or server-wins strategy", "id": "'$id'", "server_item": '$current_item'}'
                    log "UPDATE Conflict for $id in $entity (Server Wins or older client timestamp)."
                fi
            fi
            ;;
        "DELETE")
            local item_to_delete=$(echo "$db_content" | jq -r --arg entity "$entity" --arg id "$id" '.[$entity][] | select(.id == $id)')
            if [ -z "$item_to_delete" ]; then
                # Item already deleted or never existed, consider it a success for idempotency
                response='{"status": "success", "operation": "delete_noop", "id": "'$id'", "message": "Item not found or already deleted"}'
                log "DELETE no-op for $id in $entity (already deleted or never existed)."
            else
                 # Optional: Add conflict check for delete, e.g. if item was modified after client's decision to delete
                local server_timestamp=$(echo "$item_to_delete" | jq -r '.last_modified')
                local conflict_resolution=$(echo "$request_body" | jq -r '.conflict_resolution // "force-delete"') # default to force delete

                if [ "$conflict_resolution" == "force-delete" ] || [[ "$client_timestamp" > "$server_timestamp" ]]; then
                    db_content=$(echo "$db_content" | jq --arg entity "$entity" --arg id "$id" 'del(.['$entity'][] | select(.id == $id))')
                    write_db "$db_content"
                    response='{"status": "success", "operation": "delete", "id": "'$id'"}'
                    log "DELETE success for $id in $entity."
                else
                    response='{"status": "conflict", "message": "Server version is newer, delete rejected", "id": "'$id'", "server_item": '$item_to_delete'}'
                    log "DELETE conflict for $id in $entity (server version newer)."
                fi
            fi
            ;;
        "GET_ALL")
             response=$(echo "$db_content" | jq --arg entity "$entity" '{status: "success", data: .[$entity]}')
             log "GET_ALL for $entity"
            ;;
        "GET_ONE")
            local item=$(echo "$db_content" | jq -r --arg entity "$entity" --arg id "$id" '.[$entity][] | select(.id == $id)')
            if [ -z "$item" ]; then
                response='{"status": "error", "message": "Item not found", "id": "'$id'"}'
                log "GET_ONE Error: Item $id not found in $entity."
            else
                response='{"status": "success", "data": '$item'}'
                log "GET_ONE success for $id in $entity."
            fi
            ;;
        *)
            response='{"status": "error", "message": "Invalid action type"}'
            log "Invalid action type: $action_type"
            echo "$response"
            return 400 # HTTP Bad Request
            ;;
    esac

    echo "$response"
    return 0
}


# Main execution: Read from stdin for simplicity in CLI testing
# In a real server, this would listen on a port.
if [ -p /dev/stdin ]; then
    # If there's piped input
    REQUEST_DATA=$(cat)
    handle_request "$REQUEST_DATA"
else
    # If called directly with arguments (for simple GET tests perhaps)
    # Example: ./mock_server.sh '{"type": "GET_ALL", "entity": "users"}'
    if [ "$#" -gt 0 ]; then
        handle_request "$1"
    else
        log "Mock server started. Waiting for piped input or argument."
        echo '{"status": "idle", "message": "Mock server is running. Send JSON request via stdin or argument."}'
    fi
fi
