#!/bin/bash

# Mock Locale Setter for cli-localized-error-capture task
# This script simulates setting locale environment variables for testing.
# It will then execute the command passed to it as arguments.

# Usage: ./mock_locale_setter.sh <LOCALE_STRING> <COMMAND_TO_RUN> [ARGS_FOR_COMMAND...]
# Example: ./mock_locale_setter.sh "es_ES.UTF-8" ./example_cli_tool.sh some_action

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <LOCALE_STRING> <COMMAND_TO_RUN> [ARGS_FOR_COMMAND...]" >&2
    exit 1
fi

LOCALE_TO_SET="$1"
shift
COMMAND_TO_RUN="$1"
shift
COMMAND_ARGS=("$@")

# Unset common locale variables first to ensure a clean slate for LANG
unset LC_ALL
unset LC_MESSAGES
unset LANGUAGE

# Set LANG. This is the primary variable many systems use.
export LANG="$LOCALE_TO_SET"

# Optionally, set CLI_ERROR_LOCALE if the framework uses it for override
# For this mock, we assume the framework primarily checks LANG/LC_ALL/LC_MESSAGES
# export CLI_ERROR_LOCALE="$LOCALE_TO_SET" # Or a simplified form like "es"

echo "[Mock Locale Setter] Environment prepared with LANG=$LANG" >&2
echo "[Mock Locale Setter] Running command: $COMMAND_TO_RUN ${COMMAND_ARGS[*]}" >&2

# Execute the provided command with the new locale settings
"$COMMAND_TO_RUN" "${COMMAND_ARGS[@]}"

exit $?
