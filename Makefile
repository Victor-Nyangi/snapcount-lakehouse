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

SEASON ?= 2025

.PHONY: smoke
smoke: ## Real nflverse download into ./.lake-local (network to GitHub; no AWS)
	uv run python -m lake_ingest --season $(SEASON) --local .lake-local

.PHONY: tf-check
tf-check: ## terraform fmt/validate/test with a mocked provider (no AWS)
	terraform fmt -check -recursive infra
	terraform -chdir=infra/bootstrap init -backend=false -input=false >/dev/null
	terraform -chdir=infra/bootstrap validate
	terraform -chdir=infra/lake init -backend=false -input=false >/dev/null
	terraform -chdir=infra/lake validate
	terraform -chdir=infra/lake test

DBT := uv run dbt
DBT_ARGS := --project-dir transform --profiles-dir transform

.PHONY: dbt-check
dbt-check: ## dbt parse + sqlfluff lint (no warehouse connection)
	LAKE_BUCKET=$${LAKE_BUCKET:-parse-only} $(DBT) parse $(DBT_ARGS)
	uv run sqlfluff lint transform/models transform/tests --dialect athena

.PHONY: check
check: lint test-local tf-check dbt-check ## Everything CI runs, locally
