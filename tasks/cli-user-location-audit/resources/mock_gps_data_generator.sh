#!/bin/bash

# Mock GPS Data Generator
# Outputs a series of predefined or slightly randomized GPS data points as JSON lines.
# This is for testing the `add` command of the location audit tool.

# Predefined data points to cycle through or output randomly
# Format: lat,lon,accuracy,userId,deviceId,customMetadataJsonString
PREDEFINED_DATA=(
    "34.052235,-118.243683,5,user_1,device_A,\"{\\\"source\\\":\\\"mobile_app\\\",\\\"battery_level\\\":85}\""
    "34.052800,-118.243000,10,user_1,device_A,\"{\\\"source\\\":\\\"mobile_app\\\",\\\"battery_level\\\":82}\"" # Enters DowntownOffice
    "33.920000,-118.070000,15,user_2,device_B,\"{\\\"activity\\\":\\\"driving\\\"}\"" # Enters WarehouseDistrict
    "40.713000,-74.005500,8,user_3,device_C,\"{\\\"purpose\\\":\\\"maintenance\\\"}\"" # Enters RestrictedAreaA
    "34.070000,-118.240000,20,user_1,device_A,\"{\\\"event\\\":\\\"park_visit\\\"}\"" # Enters LargePark
    "34.050000,-118.240000,5,user_1,device_A,\"{\\\"source\\\":\\\"mobile_app\\\",\\\"battery_level\\\":70}\"" # Exits DowntownOffice, still in LargePark
    "33.800000,-118.000000,25,user_2,device_B,\"{\\\"status\\\":\\\"idle\\\"}\"" # Exits WarehouseDistrict
    "40.714000,-74.004500,12,user_3,device_C,\"{\\\"notes\\\":\\\"leaving_restricted\\\"}\"" # Exits RestrictedAreaA
    "34.000000,-118.000000,30,user_invalid,,\\\"{}\\\"" # Missing deviceId, for testing optional fields
    "INVALID_LAT,INVALID_LON,10,user_err,device_err,\"{\\\"error\\\":true}\"" # Invalid lat/lon for validation test
)

# $1: Number of records to generate (optional, default 1)
# $2: Mode - "sequence" or "random" (optional, default sequence)
# $3: Start index for sequence mode (optional, default 0)

num_records=${1:-1}
mode=${2:-"sequence"}
start_index=${3:-0}

generate_record() {
    local data_line="$1"
    IFS=',' read -r lat lon acc uid did meta <<< "$data_line"

    # Basic randomization if values are to be slightly varied (not implemented here for simplicity)
    # lat=$(echo "$lat + (RANDOM % 100 - 50) * 0.00001" | bc -l)
    # lon=$(echo "$lon + (RANDOM % 100 - 50) * 0.00001" | bc -l)

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

    # Construct JSON, be careful with optional fields
    local json_output
    json_output=$(jq -n \
        --arg ts "$timestamp" \
        --arg lat "$lat" \
        --arg lon "$lon" \
        --arg acc "$acc" \
        --arg uid "$uid" \
        "{timestamp: \$ts, latitude: \$lat, longitude: \$lon, accuracy: \$acc, userId: \$uid}")

    if [ -n "$did" ] && [ "$did" != "null" ]; then
        json_output=$(echo "$json_output" | jq --arg did "$did" '. + {deviceId: $did}')
    fi
    if [ -n "$meta" ] && [ "$meta" != "null" ]; then
        # Ensure meta is valid JSON or handle error. For mock, assume it's pre-validated.
        json_output=$(echo "$json_output" | jq --argjson cm "$meta" '. + {customMetadata: $cm}')
    fi
    echo "$json_output"
}

current_idx=$start_index
for ((i=0; i<num_records; i++)); do
    if [ "$mode" == "random" ]; then
        current_idx=$((RANDOM % ${#PREDEFINED_DATA[@]}))
    fi

    # Cycle through predefined data in sequence mode
    idx_to_use=$((current_idx % ${#PREDEFINED_DATA[@]}))

    generate_record "${PREDEFINED_DATA[$idx_to_use]}"

    current_idx=$((current_idx + 1))
done
