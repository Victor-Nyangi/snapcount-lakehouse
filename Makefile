# snapcount-lakehouse. Local targets only touch this laptop; AWS targets are added in Task 6.
.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help lint test-local

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  %-12s %s\n", $$1, $$2}'

lint: ## ruff check + format check
	uv run ruff check .
	uv run ruff format --check .

test-local: ## Python unit tests (no network, no AWS)
	uv run pytest -q
