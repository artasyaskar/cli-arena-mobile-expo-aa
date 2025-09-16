#!/bin/bash

# Mock for Linux 'secret-tool' (libsecret) for cli-secure-token-storage task

# secret-tool store --label='My App Token' myapp_service myapp_user
# secret-tool lookup myapp_service myapp_user
# secret-tool clear myapp_service myapp_user
# secret-tool search --all --unlock

SECRET_DB_FILE="${MOCK_LIBSECRET_DB_FILE:-./mock_libsecret.db}" # Store attributes (key=value pairs) and secret
# Format: serialized_attributes|secret_value
# Attributes: "service=myservice\nuser=myuser\nlabel=My Label" (newline separated)

SERVICE_ATTRIBUTE_KEY="clitest_service_attr" # Used to find our items
LABEL_PREFIX="clitest_label_"

log_mock() {
    echo "MOCK_LIBSECRET_LINUX: $1" >&2
}

ensure_db_file() {
    touch "$SECRET_DB_FILE"
}

# Helper to serialize attributes for storage
# Input: pairs like "key1=value1" "key2=value2"
# Output: "key1=value1\nkey2=value2"
serialize_attributes() {
    local result=""
    for pair in "$@"; do
        if [ -z "$result" ]; then
            result="$pair"
        else
            result="${result}\n${pair}"
        fi
    done
    echo - "$result" # echo - adds trailing newline, strip it
}

# Helper to deserialize attributes from storage
# Input: "key1=value1\nkey2=value2"
# Output: Bash associative array declaration: declare -A attrs=( [key1]="value1" [key2]="value2" )
deserialize_attributes() {
    local input_str="$1"
    local declaration="declare -A attrs=("
    local first=true
    echo -e "$input_str" | while IFS='=' read -r key value; do
        # Sanitize key and value for declaration (basic, not foolproof)
        key_sanitized=$(echo "$key" | sed "s/'/'\\\\''/g; s/\"/\\\\\"/g")
        value_sanitized=$(echo "$value" | sed "s/'/'\\\\''/g; s/\"/\\\\\"/g")
        if $first; then
            declaration+="['$key_sanitized']='$value_sanitized'"
            first=false
        else
            declaration+=" ['$key_sanitized']='$value_sanitized'"
        fi
    done
    declaration+=")"
    echo "$declaration"
}

# Helper to check if all query attributes match stored attributes
# $1: query attributes string "key1=val1\nkey2=val2"
# $2: stored attributes string "key1=val1\nkey2=val2\nkey3=val3"
attributes_match() {
    local query_attrs_str="$1"
    local stored_attrs_str="$2"

    local all_match=true
    # For each query attribute
    echo -e "$query_attrs_str" | while IFS='=' read -r q_key q_value; do
        local found_match_for_q_key=false
        # Check against each stored attribute
        echo -e "$stored_attrs_str" | while IFS='=' read -r s_key s_value; do
            if [ "$q_key" == "$s_key" ] && [ "$q_value" == "$s_value" ]; then
                found_match_for_q_key=true
                break
            fi
        done
        if ! $found_match_for_q_key; then
            all_match=false
            break
        fi
    done
    echo "$all_match"
}


store_secret() {
    local label=""
    local attributes_arr=() # Store key=value pairs

    # Parse arguments: secret-tool store --label='My Label' key1 val1 key2 val2 ...
    # The actual secret is read from stdin.
    # For mock, we'll take secret as the last argument if stdin is not used for simplicity.

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --label=*)
                label="${1#*=}"
                ;;
            --label)
                label="$2"
                shift
                ;;
            *) # These are attribute key-value pairs
                # service_name user_name -> service=service_name user=user_name
                # This is a simplification. Real secret-tool takes key value pairs.
                # Our solution.sh will use 'service' and 'account' as fixed attribute keys.
                if [ -z "${attributes_arr[0]}" ]; then
                    attributes_arr+=("service=$1")
                elif [ -z "${attributes_arr[1]}" ]; then
                     attributes_arr+=("account=$1")
                fi
                ;;
        esac
        shift
    done

    if [ -z "$label" ]; then
        label="${LABEL_PREFIX}default_label_$(date +%s)"
    else
        label="${LABEL_PREFIX}${label}" # Ensure our test labels are distinct
    fi
    attributes_arr+=("label=$label") # Add label as an attribute too

    # Read secret from stdin (or take last arg if stdin is empty)
    local secret_value
    if [ -p /dev/stdin ]; then
        secret_value=$(cat)
    else
        # This part is tricky as the last args were consumed by attribute parsing.
        # The solution script should always pipe the secret to stdin for `secret-tool store`.
        log_mock "ERROR: secret-tool store expects secret from stdin."
        exit 1
    fi

    if [ ${#attributes_arr[@]} -eq 0 ] || [ -z "$secret_value" ]; then
        log_mock "ERROR: secret-tool store missing attributes or secret."
        exit 1
    fi

    ensure_db_file
    local serialized_attrs=$(serialize_attributes "${attributes_arr[@]}")

    # secret-tool store typically overwrites if attributes match exactly.
    # For simplicity, our mock will overwrite if service & account match.
    local service_val=$(echo -e "$serialized_attrs" | grep "^service=" | cut -d'=' -f2)
    local account_val=$(echo -e "$serialized_attrs" | grep "^account=" | cut -d'=' -f2)

    local temp_db_file="$SECRET_DB_FILE.tmp"
    local found_and_updated=false

    # Read line by line to update or append
    # This is complex. A simpler mock might just append and let lookup find the latest.
    # Real secret-tool replaces if item with *identical attributes* exists.
    # Let's simplify: if an item with the same 'service' and 'account' attribute exists, replace it.

    # Clear existing entry with same service & account for simplicity (real secret-tool is more nuanced)
    local existing_line_num=$(awk -F'|' -v srv="$service_val" -v acc="$account_val" '
        BEGIN{OFS=FS}
        {
            split($1, attrs, "\n");
            current_srv=""; current_acc="";
            for (i in attrs) {
                if (attrs[i] ~ /^service=/) current_srv = substr(attrs[i], 9);
                if (attrs[i] ~ /^account=/) current_acc = substr(attrs[i], 9);
            }
            if (current_srv == srv && current_acc == acc) print NR;
        }
    ' "$SECRET_DB_FILE")

    if [ -n "$existing_line_num" ]; then
        sed -i.bak "${existing_line_num}d" "$SECRET_DB_FILE"
        rm -f "${SECRET_DB_FILE}.bak"
    fi

    echo -e "${serialized_attrs}|${secret_value}" >> "$SECRET_DB_FILE"
    log_mock "Stored secret with label '$label'."
    exit 0
}

lookup_secret() {
    # Args are attribute key-value pairs: service myapp_service account myapp_user
    local query_attributes_arr=()
    local key=""
    while [ "$#" -gt 0 ]; do
        if [ -z "$key" ]; then
            key="$1"
        else
            query_attributes_arr+=("$key=$1")
            key=""
        fi
        shift
    done

    if [ ${#query_attributes_arr[@]} -eq 0 ]; then
        log_mock "ERROR: secret-tool lookup missing attribute criteria."
        exit 1
    fi

    ensure_db_file
    local query_attrs_str=$(serialize_attributes "${query_attributes_arr[@]}")
    local found_secret=""

    # Read DB file line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        local stored_attrs_part="${line%|*}"
        local secret_part="${line#*|}"

        if [[ $(attributes_match "$query_attrs_str" "$stored_attrs_part") == "true" ]]; then
            found_secret="$secret_part"
            break # Found first match
        fi
    done < "$SECRET_DB_FILE"

    if [ -n "$found_secret" ]; then
        echo -n "$found_secret" # secret-tool prints to stdout, no trailing newline for password
        log_mock "Lookup successful for attributes: $query_attrs_str"
        exit 0
    else
        log_mock "Secret not found for attributes: $query_attrs_str"
        # secret-tool: The secret was not found
        echo "secret-tool: The secret was not found" >&2
        exit 1
    fi
}

clear_secret() {
    # Args are attribute key-value pairs, similar to lookup
    local query_attributes_arr=()
    local key=""
    while [ "$#" -gt 0 ]; do
        if [ -z "$key" ]; then
            key="$1"
        else
            query_attributes_arr+=("$key=$1")
            key=""
        fi
        shift
    done

    if [ ${#query_attributes_arr[@]} -eq 0 ]; then
        log_mock "ERROR: secret-tool clear missing attribute criteria."
        exit 1
    fi

    ensure_db_file
    local query_attrs_str=$(serialize_attributes "${query_attributes_arr[@]}")
    local temp_db_file="$SECRET_DB_FILE.clearing"
    local cleared_count=0

    # Create a new DB file excluding matching entries
    > "$temp_db_file" # Create empty temp file
    while IFS= read -r line || [[ -n "$line" ]]; do
        local stored_attrs_part="${line%|*}"
        # local secret_part="${line#*|}" # Not needed for clear logic

        if [[ $(attributes_match "$query_attrs_str" "$stored_attrs_part") == "true" ]]; then
            cleared_count=$((cleared_count + 1))
            # Don't write this line to temp_db_file
        else
            echo "$line" >> "$temp_db_file"
        fi
    done < "$SECRET_DB_FILE"

    mv "$temp_db_file" "$SECRET_DB_FILE"

    if [ "$cleared_count" -gt 0 ]; then
        log_mock "Cleared $cleared_count secret(s) matching attributes: $query_attrs_str"
        exit 0
    else
        log_mock "No secrets found to clear for attributes: $query_attrs_str"
        # secret-tool might exit 0 even if nothing cleared. Let's be consistent.
        exit 0 # Or 1 if we want to signal "not found" as an error for tests
    fi
}

search_secrets() {
    # Simplification: list service and account for all items matching our test prefix
    # Real `search` is more complex (e.g., --all, specific attributes)
    ensure_db_file
    log_mock "Searching for secrets (mock lists service/account for test items):"

    local count=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        local stored_attrs_part="${line%|*}"
        local service_val=""
        local account_val=""

        echo -e "$stored_attrs_part" | while IFS='=' read -r key value; do
             if [ "$key" == "service" ]; then service_val="$value"; fi
             if [ "$key" == "account" ]; then account_val="$value"; fi
        done

        # Check if it's one of our test items by label prefix or some other marker
        if echo "$stored_attrs_part" | grep -q "label=${LABEL_PREFIX}"; then
            echo "  Service: $service_val, Account: $account_val"
            count=$((count + 1))
        fi
    done < "$SECRET_DB_FILE"

    log_mock "Found $count test items."
    exit 0
}

# --- Main command parsing ---
if [ "$MOCK_LIBSECRET_FAIL" == "true" ]; then
    log_mock "Simulating 'secret-tool' command failure."
    exit 127 # Command not found or generic error
fi

ensure_db_file # Ensure DB file exists for operations

COMMAND="$1"
shift

case "$COMMAND" in
    store)
        store_secret "$@"
        ;;
    lookup)
        lookup_secret "$@"
        ;;
    clear)
        clear_secret "$@"
        ;;
    search) # Simplified for listing
        search_secrets "$@"
        ;;
    *)
        log_mock "ERROR: Unknown 'secret-tool' command: $COMMAND"
        log_mock "Supported: store, lookup, clear, search"
        exit 1
        ;;
esac

exit 127 # Should be unreachable
