#!/usr/bin/env bash
# This script provides the solution for the 'db-migration-task' task.

set -euo pipefail

echo "Solving the 'db-migration-task'..."

# 1. Start the Docker environment to allow running commands
echo "Starting Docker environment..."
docker-compose up -d --build
sleep 5 # Wait for containers to be ready

# 2. Create the new migration file
echo "Creating the new migration file..."
# The name can be anything, but 'add_status_to_users' is descriptive.
MIGRATION_NAME="add_status_to_users"
# Use docker-compose exec to run knex inside the container
MIGRATION_FILE_PATH=$(docker-compose exec -T app npx knex migrate:make $MIGRATION_NAME | grep "Created Migration" | sed 's/Created Migration: //')
# Get just the filename
MIGRATION_FILENAME=$(basename $MIGRATION_FILE_PATH)
echo "Created migration file: $MIGRATION_FILENAME"

# 3. Write the migration logic into the new file.
# This is the core of the solution.
echo "Writing the migration logic..."
# We use a heredoc to write the content to the migration file.
# Note: The file path is inside the container, so we must use docker-compose exec to write it.
docker-compose exec -T app bash -c "cat > /usr/src/app/migrations/$MIGRATION_FILENAME" <<'MIGRATION_LOGIC'
/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.up = function(knex) {
  return knex.schema.alterTable('users', function(table) {
    // 1. Add the new 'status' column, with a default value for new rows
    // and making it not nullable.
    table.string('status').notNullable().defaultTo('active');
  }).then(function() {
    // 2. Update all existing rows to have the 'active' status.
    // This is crucial for data integrity.
    return knex('users').update({ status: 'active' });
  });
};

/**
 * @param { import("knex").Knex } knex
 * @returns { Promise<void> }
 */
exports.down = function(knex) {
  return knex.schema.alterTable('users', function(table) {
    table.dropColumn('status');
  });
};
MIGRATION_LOGIC

echo "Migration logic written successfully."

# 4. Run all migrations
echo "Running all database migrations..."
docker-compose exec -T app npx knex migrate:latest

echo "Migrations are complete."
echo "You can now run the verify.sh script to check the solution."
echo "Or run 'docker-compose exec app npm test' to run the tests yourself."
