# ==============================================================================
# ShopLite Makefile — Question 2.d Automation Target Specifications
# Checkpoint Command: make up && make smoke
# ==============================================================================

.PHONY: build up down test smoke help

help:
	@echo "Available Make targets for ShopLite:"
	@echo "  make build  - Build all microservice container images"
	@echo "  make up     - Start all 5 services in detached mode"
	@echo "  make down   - Stop and remove containers and volumes"
	@echo "  make test   - Run unit tests with pytest"
	@echo "  make smoke  - Run automated end-to-end smoke test suite"

build:
	docker compose build

up:
	docker compose up -d

down:
	docker compose down -v

test:
	pytest tests/ -v

smoke:
	chmod +x scripts/smoke-test.sh
	./scripts/smoke-test.sh
