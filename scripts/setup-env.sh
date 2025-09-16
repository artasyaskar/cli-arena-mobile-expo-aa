#!/bin/bash

# Script to help set up the development environment.
# This might include checks for dependencies, configuration steps, etc.

echo "Running environment setup script..."

# Check for Docker
if ! command -v docker &> /dev/null
then
    echo "Docker could not be found. Please install Docker."
    # exit 1 # Optionally exit if Docker is critical
else
    echo "Docker is installed."
fi

# Check for Docker Compose (v1 or v2)
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null
then
    echo "Docker Compose could not be found. Please install Docker Compose (either v1 standalone or v2 plugin)."
    # exit 1 # Optionally exit
else
    if command -v docker-compose &> /dev/null; then
        echo "Docker Compose v1 is installed."
    elif docker compose version &> /dev/null; then
        echo "Docker Compose v2 (plugin) is installed."
    fi
fi

# Check for Node.js and npm
if ! command -v node &> /dev/null || ! command -v npm &> /dev/null
then
    echo "Node.js or npm could not be found. Please install Node.js (which includes npm)."
    # exit 1
else
    echo "Node.js version: $(node -v)"
    echo "npm version: $(npm -v)"
fi

# Check for Supabase CLI (optional, as Makefile uses Docker Compose primarily)
# if ! command -v supabase &> /dev/null
# then
#     echo "Supabase CLI is not installed. For advanced Supabase operations, consider installing it: npm install -g supabase"
# else
#     echo "Supabase CLI is installed. Version: $(supabase -v)"
# fi


# Placeholder for other environment checks or setup steps:
# - Check for Java/Kotlin SDK for Android
# - Check for Swift toolchain for iOS (on macOS)
# - Create a default .env file from .env.example if it doesn't exist
#   if [ ! -f .env ] && [ -f .env.example ]; then
#       echo "Creating .env file from .env.example..."
#       cp .env.example .env
#   fi

echo "Environment setup script finished."
echo "Ensure you have configured any necessary environment variables (e.g., in a .env file if used by the project)."
echo "Next steps: Run 'make setup' to install dependencies and initialize services."

exit 0
