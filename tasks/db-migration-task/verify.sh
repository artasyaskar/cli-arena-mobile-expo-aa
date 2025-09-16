#!/usr/bin/env bash
set -euo pipefail

echo "🔥 Verifying 'High-Stakes Database Migration' Task"
echo "================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

# Function to print success messages
success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Function to print error messages
error() {
    echo -e "${RED}❌ $1${NC}"
    FAILED=1
}

# Cleanup function to always run on exit
cleanup() {
    echo "🧹 Cleaning up..."
    docker-compose down -v --remove-orphans > /dev/null 2>&1
}

# Trap the exit signal to run cleanup
trap cleanup EXIT

# --- Verification Steps ---

# 1. Start the Docker environment
echo "1. Starting the environment with Docker Compose..."
docker-compose up -d --build
# Wait for the database to be ready
echo "   Waiting for the database to accept connections..."
sleep 10 # Simple but effective wait

# 2. Set up the initial state (run first migration and seed)
echo "2. Setting up the initial database state..."
docker-compose exec -T app npx knex migrate:latest > /dev/null
# Create a seed file to add some initial users
cat > app/seeds/initial_users.js <<'SEED'
module.exports.seed = async function(knex) {
  // Deletes ALL existing entries
  await knex('users').del();
  // Inserts seed entries
  await knex('users').insert([
    { name: 'Alice', email: 'alice@example.com' },
    { name: 'Bob', email: 'bob@example.com' },
  ]);
};
SEED
docker-compose exec -T app npx knex seed:run > /dev/null
success "Initial database schema and seed data created."

# 3. Check for a new migration file from the user
echo "3. Looking for the new migration file..."
# Find any migration file that is NOT the initial one.
# Note: This is a simple check. A more robust check might be needed.
USER_MIGRATION=$(find app/migrations -type f -name "*.js" ! -name "*_create_users_table.js")
if [ -n "$USER_MIGRATION" ]; then
    success "New migration file found: $(basename $USER_MIGRATION)"
else
    error "No new migration file was found in the app/migrations directory."
fi

# 4. Run the user's migration (which is now the latest)
echo "4. Applying all migrations (including the user's)..."
if docker-compose exec -T app npx knex migrate:latest > /tmp/migration.log 2>&1; then
    success "Migrations applied successfully."
else
    error "The migration command failed. Check the logs."
    cat /tmp/migration.log
fi

# 5. Run the tests
echo "5. Running the test suite..."
if docker-compose exec -T app npm test > /tmp/tests.log 2>&1; then
    success "All tests passed successfully!"
else
    error "The test suite failed. This means the API is not behaving as expected after the migration."
    echo "--- Test Logs ---"
    cat /tmp/tests.log
fi

# 6. Directly verify the database schema and data
echo "6. Directly verifying the database..."
DB_CHECK_CMD="psql -U user -d app_db -c"
# Check if the 'status' column exists
if docker-compose exec -T db $DB_CHECK_CMD "\d users" | grep -q "status"; then
    success "The 'status' column exists in the 'users' table."
else
    error "The 'status' column was not found in the 'users' table."
fi

# Check if the 'status' column for existing users is not null and is 'active'
COUNT_NULL=$(docker-compose exec -T db $DB_CHECK_CMD "SELECT COUNT(*) FROM users WHERE status IS NULL;" | sed -n 3p | tr -d '[:space:]')
if [ "$COUNT_NULL" = "0" ]; then
    success "No users have a NULL status."
else
    error "Found users with a NULL status. All existing users should have their status populated."
fi

# --- Final Summary ---
echo "------------------------------------------------------"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All verification checks passed! The migration was a success!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some verification checks failed. Please review the errors above.${NC}"
    exit 1
fi
