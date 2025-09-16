#!/bin/bash

# Mock for Windows Credential Manager (via PowerShell) for cli-secure-token-storage task
# This script simulates the behavior of PowerShell cmdlets for credential management.
# It interacts with a simple text file as a mock credential store.

CREDMAN_DB_FILE="${MOCK_CREDMAN_DB_FILE:-./mock_credman.db}" # Store target, username, password triples
TARGET_PREFIX="clitest_win_" # Namespace for tests

log_mock() {
    echo "MOCK_CREDMAN_WINDOWS: $1" >&2
}

ensure_db_file() {
    touch "$CREDMAN_DB_FILE"
}

# Simulates:
# $Password = ConvertTo-SecureString "MyPassword" -AsPlainText -Force
# New-StoredCredential -Target <TargetName> -User <UserName> -Password $Password
# Or, if using CredentialManager module:
# Write-StoredCredential -TargetName <TargetName> -UserName <UserName> -Password "MyPassword"
store_credential() {
    local target_name=""
    local user_name=""
    local password_str="" # Plain text password for mock

    # Simplified parsing, assumes -TargetName, -UserName, -Password flags
    # Or positional if called like `powershell.exe -Command Write-StoredCredential ...`
    # For this mock, we'll expect named parameters to be passed to the script directly.
    # e.g. ./mock_credential_manager_windows.sh Write-StoredCredential -TargetName service -UserName user -Password pass

    shift # remove Write-StoredCredential
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -TargetName|-Target) target_name="$2"; shift ;;
            -UserName|-User) user_name="$2"; shift ;;
            -Password) password_str="$2"; shift ;; # Expect plain text for mock
            *) ;;
        esac
        shift
    done

    if [ -z "$target_name" ] || [ -z "$user_name" ] || [ -z "$password_str" ]; then
        log_mock "ERROR: Write-StoredCredential missing TargetName, UserName, or Password."
        exit 1
    fi

    ensure_db_file
    target_key="${TARGET_PREFIX}${target_name}"

    # PowerShell's Write-StoredCredential overwrites by default.
    if grep -q "^${target_key}|${user_name}|" "$CREDMAN_DB_FILE"; then
        sed -i.bak "/^${target_key}|${user_name}|/d" "$CREDMAN_DB_FILE"
        rm -f "${CREDMAN_DB_FILE}.bak"
    fi
    echo "${target_key}|${user_name}|${password_str}" >> "$CREDMAN_DB_FILE"
    log_mock "Stored credential for Target '$target_key' User '$user_name'."
    exit 0
}

# Simulates:
# $Cred = Read-StoredCredential -Target <TargetName> -User <UserName>
# $Cred.Password | ForEach-Object { Write-Host $_ }
# Or $Cred.GetNetworkCredential().Password
retrieve_credential() {
    local target_name=""
    local user_name=""

    shift # remove Read-StoredCredential
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -TargetName|-Target) target_name="$2"; shift ;;
            -UserName|-User) user_name="$2"; shift ;;
            *) ;;
        esac
        shift
    done

    if [ -z "$target_name" ] || [ -z "$user_name" ]; then
        log_mock "ERROR: Read-StoredCredential missing TargetName or UserName."
        exit 1 # Or specific error code
    fi

    ensure_db_file
    target_key="${TARGET_PREFIX}${target_name}"

    local entry=$(grep "^${target_key}|${user_name}|" "$CREDMAN_DB_FILE")

    if [ -n "$entry" ]; then
        # Real cmdlet returns an object. We just output the password.
        echo "$entry" | cut -d'|' -f3
        log_mock "Retrieved credential for Target '$target_key' User '$user_name'."
        exit 0
    else
        log_mock "Credential not found for Target '$target_key' User '$user_name'."
        # Real cmdlet might return $null or throw an error. Let's exit with error.
        exit 1 # Generic error, or a specific one like "Element not found"
    fi
}

# Simulates:
# Remove-StoredCredential -Target <TargetName> -User <UserName>
delete_credential() {
    local target_name=""
    local user_name=""

    shift # remove Remove-StoredCredential
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -TargetName|-Target) target_name="$2"; shift ;;
            -UserName|-User) user_name="$2"; shift ;;
            *) ;;
        esac
        shift
    done

    if [ -z "$target_name" ] || [ -z "$user_name" ]; then
        log_mock "ERROR: Remove-StoredCredential missing TargetName or UserName."
        exit 1
    fi

    ensure_db_file
    target_key="${TARGET_PREFIX}${target_name}"

    if grep -q "^${target_key}|${user_name}|" "$CREDMAN_DB_FILE"; then
        sed -i.bak "/^${target_key}|${user_name}|/d" "$CREDMAN_DB_FILE"
        rm -f "${CREDMAN_DB_FILE}.bak"
        log_mock "Removed credential for Target '$target_key' User '$user_name'."
        exit 0
    else
        log_mock "Credential not found for Target '$target_key' User '$user_name'. Nothing to remove."
        # Real cmdlet might not error if not found. For testing, an error is useful.
        exit 1 # Or specific error
    fi
}

# Simulates listing (e.g. Get-StoredCredential from a module, or enumerating vault)
# For this mock, we'll just list all known generic passwords by our prefix
list_credentials() {
    ensure_db_file
    log_mock "Listing known credentials:"
    grep "^${TARGET_PREFIX}" "$CREDMAN_DB_FILE" | while IFS='|' read -r full_target user_name pass; do
        local display_target=${full_target#"$TARGET_PREFIX"}
        echo "  Target: $display_target, User: $user_name"
    done
    exit 0
}


# --- Main command parsing ---
# The script expects the first argument to be the cmdlet name.
# e.g. ./mock_credential_manager_windows.sh Write-StoredCredential -TargetName service -User user -Password pass

if [ "$MOCK_CREDMAN_FAIL" == "true" ]; then
    log_mock "Simulating PowerShell Credential Manager command failure."
    # Simulate powershell.exe not found or cmdlet error
    exit 127 # Command not found, or a generic PowerShell error code
fi

ensure_db_file # Ensure DB exists for any operation

COMMAND_NAME="$1"

case "$COMMAND_NAME" in
    Write-StoredCredential|New-StoredCredential)
        store_credential "$@"
        ;;
    Read-StoredCredential)
        retrieve_credential "$@"
        ;;
    Remove-StoredCredential)
        delete_credential "$@"
        ;;
    Get-StoredCredentialList) # Made-up command for listing for test purposes
        list_credentials "$@"
        ;;
    *)
        log_mock "ERROR: Unknown PowerShell credential command: $COMMAND_NAME"
        log_mock "Supported: Write-StoredCredential, Read-StoredCredential, Remove-StoredCredential, Get-StoredCredentialList"
        exit 1
        ;;
esac

exit 127 # Should be unreachable if a command matched
