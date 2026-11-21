# ==============================================================================
# ShopLite Makefile — Question 2.d Automation Target Specifications
# Checkpoint Command: make up && make smoke
# ==============================================================================

.PHONY: build up down test smoke lint guardrails help

help:
	@echo "Available Make targets for ShopLite:"
	@echo "  make build      - Build all microservice container images"
	@echo "  make up         - Start all 5 services in detached mode"
	@echo "  make down       - Stop and remove containers and volumes"
	@echo "  make test       - Run unit tests with pytest"
	@echo "  make smoke      - Run automated end-to-end smoke test suite"
	@echo "  make lint       - Run code linters (Flake8)"
	@echo "  make guardrails - Run pre-commit and syntax verification"

build:
	docker compose build

up:
	docker compose up -d --build

down:
	docker compose down -v

test:
	pytest tests/ -v

lint:
	flake8 services/ --count --max-line-length=120

guardrails: lint test
	@echo "Automated guardrails verification completed successfully!"

smoke:
	chmod +x scripts/smoke-test.sh
	./scripts/smoke-test.sh
