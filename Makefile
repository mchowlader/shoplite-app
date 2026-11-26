# ==============================================================================
# ShopLite Makefile — Question 2.d Automation Targets
# Checkpoint Command: make up && make smoke
# ==============================================================================

PYTHON := $(shell command -v python3 2>/dev/null || command -v python 2>/dev/null)

.PHONY: build up down test smoke lint verify guardrails help

help:
	@echo "Available Make targets for ShopLite:"
	@echo "  make build      - Build all microservice container images"
	@echo "  make up         - Start all 5 services in detached mode"
	@echo "  make down       - Stop and remove containers and volumes"
	@echo "  make test       - Run unit tests with pytest"
	@echo "  make smoke      - Run automated end-to-end smoke test suite"
	@echo "  make lint       - Run code linters (Flake8)"
	@echo "  make verify     - Run YAML/JSON configuration syntax verification"
	@echo "  make guardrails - Run full verification suite (lint, test, verify)"

build:
	docker compose build

up:
	docker compose up -d --build

down:
	docker compose down -v

test:
	$(PYTHON) -m pytest tests/ -v

lint:
	$(PYTHON) -m flake8 services/ tests/ --count --max-line-length=120

verify:
	$(PYTHON) scripts/verify-workloads.py

guardrails: lint test verify
	@echo "Automated guardrails verification completed successfully!"

smoke:
	chmod +x scripts/smoke-test.sh
	SKIP_COMPOSE_UP=1 ./scripts/smoke-test.sh
