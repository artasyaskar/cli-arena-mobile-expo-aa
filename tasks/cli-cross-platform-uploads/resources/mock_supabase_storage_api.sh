#!/bin/bash

# Mock Supabase Storage API
# Simulates creating signed URLs and uploading files.

MOCK_STORAGE_BASE_PATH="${MOCK_STORAGE_BASE_PATH:-./mock_supabase_storage_root}"
LOG_FILE="${MOCK_STORAGE_BASE_PATH}/mock_api.log"
UPLOADED_FILES_LOG="${MOCK_STORAGE_BASE_PATH}/uploaded_files.log" # Records what was "uploaded"
MAX_BUCKET_SIZE_BYTES=$((1024 * 1024 * 10)) # 10MB mock quota for testing
CURRENT_BUCKET_SIZE_FILE="${MOCK_STORAGE_BASE_PATH}/.bucket_size"

# Dummy API key for simulation
VALID_API_KEY="FAKE_KEY_SUPABASE"

log_api() {
    echo "$(date +'%Y-%m-%dT%H:%M:%S%z') [MOCK_STORAGE_API] $1" >> "$LOG_FILE"
}

ensure_storage_dir() {
    mkdir -p "$MOCK_STORAGE_BASE_PATH"
    if [ ! -f "$CURRENT_BUCKET_SIZE_FILE" ]; then
        echo "0" > "$CURRENT_BUCKET_SIZE_FILE"
    fi
    touch "$UPLOADED_FILES_LOG" # Ensure it exists
    log_api "Mock storage base path: $MOCK_STORAGE_BASE_PATH"
}

# --- Helper: Get current bucket size ---
get_current_bucket_size() {
    if [ -f "$CURRENT_BUCKET_SIZE_FILE" ]; then
        cat "$CURRENT_BUCKET_SIZE_FILE"
    else
        echo "0"
    fi
}

# --- Helper: Update bucket size ---
# $1: size_change (positive for add, negative for delete - though delete not implemented here)
update_bucket_size() {
    local size_change=$1
    local current_size=$(get_current_bucket_size)
    local new_size=$((current_size + size_change))
    echo "$new_size" > "$CURRENT_BUCKET_SIZE_FILE"
    log_api "Bucket size updated from $current_size to $new_size bytes."
}


# --- Simulate API Endpoints ---

# Simulate POST /object/upload/sign/{bucketName}/{filePath}
# For simplicity, we'll just acknowledge and return a mock URL.
# In a real scenario, this would involve actual signing.
handle_get_signed_url() {
    local bucket_name="$1"
    local remote_path="$2"
    local http_method="$3" # Should be POST for Supabase typical signed URL for upload

    log_api "Received request for signed URL: Bucket='$bucket_name', Path='$remote_path', Method='$http_method'"

    if [ -z "$bucket_name" ] || [ -z "$remote_path" ] || [ -z "$http_method" ]; then
        log_api "Bad request for signed URL: missing parameters."
        echo '{"error": "Bad Request", "message": "Bucket name, path, and method required."}'
        return 400
    fi

    # Simulate auth check (passed via Authorization header in curl)
    # The solution.sh should set this.
    if [ -z "$HTTP_AUTHORIZATION" ] || [[ "$HTTP_AUTHORIZATION" != "Bearer $VALID_API_KEY" ]]; then
        log_api "Auth failed for signed URL. Header: $HTTP_AUTHORIZATION"
        echo '{"error": "Unauthorized", "message": "Invalid or missing API key."}'
        return 401
    fi

    # In a real scenario, you'd generate a presigned URL here.
    # For the mock, we just construct a fake URL that the uploader will use.
    local mock_upload_url="http://localhost:9999/mock_upload/$bucket_name/$remote_path?token=signed_token_for_${remote_path//\//_}"

    log_api "Generated mock signed URL: $mock_upload_url"
    echo "$(jq -n --arg url "$mock_upload_url" '{signedURL: $url, path: $remote_path}')"
    return 0
}

# Simulate PUT/POST to the signed URL (or a direct upload endpoint)
# This mock endpoint will be called by curl from solution.sh
# We'll use environment variables to pass metadata like Content-Type, Cache-Control, and expected checksum.
handle_file_upload() {
    local bucket_name="$1"
    # The rest of the path is the object key. Can be multi-level.
    shift # Remove bucket_name
    local remote_path="$*" # Remaining arguments form the path
    remote_path="${remote_path// /%20}" # Basic URL encoding for spaces in path parts

    log_api "Received file upload request: Bucket='$bucket_name', Path='$remote_path'"
    log_api "Headers: Content-Type='$CONTENT_TYPE', Cache-Control='$CACHE_CONTROL', x-upsert='$X_UPSERT'"
    log_api "Expected checksum (x-checksum-sha256): '$X_CHECKSUM_SHA256'"

    # Auth check (again, if needed, or assume signed URL implies auth)
    # For simplicity, let's assume the signed URL token implies auth for this endpoint.
    # if [[ "$REQUEST_URI" != *"?token=signed_token_for_"* ]]; then
    #     log_api "Upload failed: Invalid or missing token in URL."
    #     echo '{"error": "Forbidden", "message": "Invalid upload token."}'
    #     return 403
    # fi

    local target_dir="$MOCK_STORAGE_BASE_PATH/$bucket_name/$(dirname "$remote_path")"
    local target_file="$MOCK_STORAGE_BASE_PATH/$bucket_name/$remote_path"
    mkdir -p "$target_dir"

    # Check for existing file and upsert flag
    if [ -f "$target_file" ] && [ "$X_UPSERT" != "true" ]; then
        log_api "Upload failed: File '$remote_path' already exists in bucket '$bucket_name' and upsert is false."
        echo '{"error": "Duplicate", "message": "File already exists. Use upsert option to overwrite."}'
        return 409 # Conflict
    fi

    # Read file content from stdin (piped from curl -T - or --data-binary @-)
    local temp_file=$(mktemp)
    cat > "$temp_file"
    local file_size=$(stat -c%s "$temp_file")
    log_api "Received file data, size: $file_size bytes."

    # Quota Check
    local current_bucket_size=$(get_current_bucket_size)
    if (( current_bucket_size + file_size > MAX_BUCKET_SIZE_BYTES )); then
        log_api "Upload failed: Bucket quota exceeded. Current: $current_bucket_size, File: $file_size, Max: $MAX_BUCKET_SIZE_BYTES"
        rm "$temp_file"
        echo '{"error": "QuotaExceeded", "message": "Storage quota for the bucket has been exceeded."}'
        return 413 # Payload Too Large (or a custom quota error)
    fi

    # Checksum validation
    if [ -n "$X_CHECKSUM_SHA256" ]; then
        local calculated_checksum=$(sha256sum "$temp_file" | awk '{print $1}')
        log_api "Calculated checksum: $calculated_checksum"
        if [ "$calculated_checksum" != "$X_CHECKSUM_SHA256" ]; then
            log_api "Upload failed: Checksum mismatch. Expected '$X_CHECKSUM_SHA256', got '$calculated_checksum'."
            rm "$temp_file"
            echo '{"error": "ChecksumMismatch", "message": "The uploaded file checksum does not match the expected checksum."}'
            return 400 # Bad Request
        fi
        log_api "Checksum validation passed."
    else
        log_api "No checksum provided for validation."
    fi

    # Simulate saving the file
    mv "$temp_file" "$target_file"
    if [ $? -eq 0 ]; then
        update_bucket_size "$file_size"
        log_api "File '$remote_path' successfully 'uploaded' to bucket '$bucket_name'."
        echo "$bucket_name/$remote_path" >> "$UPLOADED_FILES_LOG" # Log successful upload
        echo '{"message": "File uploaded successfully."}'
        return 0 # OK
    else
        log_api "Failed to save file '$remote_path' to mock storage."
        echo '{"error": "Internal Server Error", "message": "Failed to save file on server."}'
        rm -f "$temp_file" # Ensure temp file is cleaned up on error
        return 500 # Internal Server Error
    fi
}

# --- Main Request Router ---
# This script is intended to be called with specific arguments to simulate different API endpoints.
# Example calls from solution.sh might be:
# ./mock_supabase_storage_api.sh GET_SIGNED_URL <bucket> <path> <method>
# Or, for uploads, it might be invoked by curl where the path is part of the URL.
# For simplicity, we'll use command-line arguments to route.

COMMAND="$1"
shift

ensure_storage_dir # Ensure base directory and log file exist

case "$COMMAND" in
    GET_SIGNED_URL)
        # $1: bucket_name, $2: remote_path, $3: http_method (e.g., POST)
        handle_get_signed_url "$1" "$2" "$3"
        exit $?
        ;;
    UPLOAD_FILE)
        # $1: bucket_name, $2...: remote_path parts
        # File content will be from stdin
        # Headers (Content-Type, Cache-Control, x-upsert, x-checksum-sha256) via env vars
        handle_file_upload "$@"
        exit $?
        ;;
    GET_BUCKET_SIZE) # Helper for testing
        get_current_bucket_size
        exit 0
        ;;
    RESET_BUCKET) # Helper for testing
        rm -rf "${MOCK_STORAGE_BASE_PATH:?}"/* # Careful with rm -rf!
        ensure_storage_dir # Recreate basic structure
        log_api "Mock storage bucket reset."
        echo '{"message": "Mock storage reset successfully."}'
        exit 0
        ;;
    *)
        log_api "Invalid command: $COMMAND"
        echo "{\"error\": \"InvalidCommand\", \"message\": \"Command not recognized by mock API.\"}"
        exit 404
        ;;
esac
