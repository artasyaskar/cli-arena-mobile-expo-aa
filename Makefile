SHELL := /bin/bash

DOCKER_COMPOSE := sudo docker compose
APP_SERVICE_NAME := app

# ========================
# DEFAULT TARGET
# ========================
.PHONY: all
all: help

# ========================
# HELP
# ========================
.PHONY: help
help:
	@echo ""
	@echo "🛠️  Available targets:"
	@echo "  setup           : Initialize Supabase local dev environment."
	@echo "  build           : Compile mobile CLI logic (TypeScript)."
	@echo "  serve           : Run the application logic via CLI. Requires TASK=<task-id>"
	@echo "  test            : Run tests (unit and integration)."
	@echo "  lint            : Lint code (ESLint)."
	@echo "  supabase-start  : Start Supabase services."
	@echo "  supabase-stop   : Stop Supabase services."
	@echo "  supabase-status : Check status of Supabase services."
	@echo "  supabase-logs   : View logs for Supabase services."
	@echo "  clean           : Remove build artifacts and node_modules."
	@echo ""

# ========================
# SETUP
# ========================
.PHONY: setup
setup: supabase-start supabase-init-db
	@echo "✅ Setup complete."

.PHONY: supabase-init-db
supabase-init-db:
	@echo "🗃️  Initializing Supabase DB..."
	@echo "ℹ️  Using docker-compose volumes for schema.sql + seed.sql."
	@echo "ℹ️  To force re-init, run 'make supabase-stop' then 'make setup' again."

# ========================
# BUILD
# ========================
.PHONY: build
build:
	@echo "🔧 Building CLI (TypeScript)..."
	$(DOCKER_COMPOSE) run --rm -T $(APP_SERVICE_NAME) npm run build

# ========================
# SERVE
# ========================
.PHONY: serve
serve:
	@echo "🚀 Serving CLI..."
	@if [ -z "$(TASK)" ]; then \
		echo "❌ Error: TASK parameter is required"; \
		echo "✅ Usage: make serve TASK=<task-id>"; \
		echo "📋 Available tasks:"; \
		$(DOCKER_COMPOSE) run --rm $(APP_SERVICE_NAME) node dist/index.js task --list || true; \
	else \
		echo "▶️  Executing task: $(TASK)"; \
		$(DOCKER_COMPOSE) run --rm $(APP_SERVICE_NAME) node dist/index.js task $(TASK); \
	fi


# ========================
# RUN (Manual)
# ========================
.PHONY: run
run:
	@echo "Running CLI manually..."
	$(DOCKER_COMPOSE) run --rm $(APP_SERVICE_NAME) npm run cli

# ========================
# TESTS
# ========================
.PHONY: test
test:
	@echo "🧪 Running tests with Jest..."
	$(DOCKER_COMPOSE) run --rm -T $(APP_SERVICE_NAME) npm test

# ========================
# LINT
# ========================
.PHONY: lint
lint:
	@echo "🔍 Linting with ESLint..."
	$(DOCKER_COMPOSE) run --rm -T $(APP_SERVICE_NAME) npm run lint

# ========================
# SUPABASE COMMANDS
# ========================
.PHONY: supabase-start
supabase-start:
	@echo "🟢 Starting Supabase services..."
	$(DOCKER_COMPOSE) up -d db auth rest realtime storage-api
	@sleep 10
	$(DOCKER_COMPOSE) ps
	@echo "✅ Supabase services started."

.PHONY: supabase-stop
supabase-stop:
	@echo "🛑 Stopping Supabase services..."
	$(DOCKER_COMPOSE) down -v --remove-orphans


.PHONY: supabase-status
supabase-status:
	@echo "📊 Supabase service status:"
	$(DOCKER_COMPOSE) ps

.PHONY: supabase-logs
supabase-logs:
	@echo "📜 Tailing Supabase logs (Ctrl+C to stop)..."
	$(DOCKER_COMPOSE) logs -f

# ========================
# CLEANUP
# ========================
.PHONY: clean
clean:
	@echo "🧹 Cleaning up..."
	rm -rf dist/ node_modules/
	@echo "✅ Clean complete."
.PHONY: list-tasks
list-tasks:
	@echo "📋 Listing CLI tasks..."
	@$(DOCKER_COMPOSE) run --rm $(APP_SERVICE_NAME) node dist/index.js task --list || true
