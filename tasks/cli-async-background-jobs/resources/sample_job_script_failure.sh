#!/bin/bash
# Sample job script that fails a few times then succeeds, or just fails.

JOB_ID="$1" # Assume job ID is passed as first argument for statefulness
STATE_FILE_DIR="${JOB_STATE_DIR:-./job_states}" # Allow override for test location
mkdir -p "$STATE_FILE_DIR"
ATTEMPT_FILE="$STATE_FILE_DIR/${JOB_ID}_attempts.txt"

# Number of times this script should fail before succeeding
# If FAIL_COUNT is 0, it succeeds on the first try.
# If FAIL_COUNT is -1, it always fails.
FAIL_COUNT="${MAX_FAILURES_FOR_SCRIPT:-2}" # Default: fail twice, succeed on 3rd attempt

CURRENT_ATTEMPT=0
if [ -f "$ATTEMPT_FILE" ]; then
    CURRENT_ATTEMPT=$(cat "$ATTEMPT_FILE")
fi
CURRENT_ATTEMPT=$((CURRENT_ATTEMPT + 1))
echo "$CURRENT_ATTEMPT" > "$ATTEMPT_FILE"

echo "Sample Failure Job (Job ID: $JOB_ID): Starting execution, attempt #$CURRENT_ATTEMPT."
echo "This job is configured to fail $FAIL_COUNT time(s) before succeeding (if FAIL_COUNT >= 0)."
echo "Arguments received (excluding job_id): ${@:2}"
echo "Simulating some work..."
sleep 2

if [ "$FAIL_COUNT" -eq -1 ]; then # Always fail
    echo "Sample Failure Job: This job is configured to always fail. Failing now on attempt #$CURRENT_ATTEMPT." >&2
    echo "Sample Failure Job: Error details to STDERR." >&2
    exit 1
elif [ "$CURRENT_ATTEMPT" -le "$FAIL_COUNT" ]; then
    echo "Sample Failure Job: Failing on attempt #$CURRENT_ATTEMPT as configured." >&2
    echo "Sample Failure Job: Specific error for attempt $CURRENT_ATTEMPT." >&2
    exit 1
else
    echo "Sample Failure Job: Succeeded on attempt #$CURRENT_ATTEMPT!"
    echo "Sample Failure Job: Output to STDOUT after successful attempt."
    # Clean up state file on success
    rm -f "$ATTEMPT_FILE"
    exit 0
fi
