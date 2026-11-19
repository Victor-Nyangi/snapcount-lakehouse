# snapcount-lakehouse
#
# Local targets (no AWS):  check lint test-local tf-check dbt-check smoke parity-seed
# AWS targets (Victor runs these, with the snapcount-lake SSO profile):
#   bootstrap up ingest build test cost down
.DEFAULT_GOAL := help
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

SEASON ?= 2025
export AWS_PROFILE ?= snapcount-lake
export AWS_REGION ?= eu-west-1

DBT := uv run dbt
DBT_ARGS := --project-dir transform --profiles-dir transform
TF_BOOT := terraform -chdir=infra/bootstrap
TF_LAKE := terraform -chdir=infra/lake
SNAPCOUNT_DUMP ?= $(HOME)/Bread/Projects/In Progress/snapcount/backfill.sql.gz

# Read from Terraform outputs at recipe time (local state reads, not AWS calls).
lake_out = $$($(TF_LAKE) output -raw $(1))
DBT_ENV = LAKE_BUCKET=$(call lake_out,data_bucket) LAKE_WORKGROUP=$(call lake_out,athena_workgroup)

.PHONY: help
help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  %-12s %s\n", $$1, $$2}'

# ---------------------------------------------------------------- local, no AWS

.PHONY: check lint test-local tf-check dbt-check smoke parity-seed
check: lint test-local tf-check dbt-check ## Everything CI runs, locally

lint: ## ruff check + format check
	uv run ruff check .
	uv run ruff format --check .

test-local: ## Python unit tests (no network, no AWS)
	uv run pytest -q

tf-check: ## terraform fmt/validate/test with a mocked provider (no AWS)
	terraform fmt -check -recursive infra
	$(TF_BOOT) init -backend=false -input=false >/dev/null
	$(TF_BOOT) validate
	$(TF_LAKE) init -backend=false -input=false >/dev/null
	$(TF_LAKE) validate
	$(TF_LAKE) test

dbt-check: ## dbt parse + sqlfluff lint (no warehouse connection)
	LAKE_BUCKET=$${LAKE_BUCKET:-parse-only} $(DBT) parse $(DBT_ARGS)
	uv run sqlfluff lint transform/models transform/tests --dialect athena

smoke: ## Real nflverse download into ./.lake-local (network to GitHub; no AWS)
	uv run python -m lake_ingest --season $(SEASON) --local .lake-local

parity-seed: ## Regenerate the parity seed for SEASON from snapcount's dump (read-only)
	uv run python scripts/parity_from_snapcount.py --dump "$(SNAPCOUNT_DUMP)" --season $(SEASON) \
		--out transform/seeds/parity_expected_$(SEASON).csv

# ---------------------------------------------------------------- AWS (Victor)

.PHONY: bootstrap lake-init up ingest build test scanned cost down

bootstrap: ## One-time: create the Terraform state bucket (local state, never destroyed)
	$(TF_BOOT) init -input=false
	$(TF_BOOT) apply

lake-init:
	@bucket=$$($(TF_BOOT) output -raw state_bucket 2>/dev/null) || { echo "no state bucket: run make bootstrap first" >&2; exit 1; }; \
	$(TF_LAKE) init -input=false -reconfigure -backend-config="bucket=$$bucket" >/dev/null

up: lake-init ## Create or update the lake stack, then print its outputs
	@test -f infra/lake/terraform.tfvars || { echo "cp infra/lake/terraform.tfvars.example infra/lake/terraform.tfvars and set budget_email" >&2; exit 1; }
	$(TF_LAKE) apply
	$(TF_LAKE) output

ingest: lake-init ## Invoke the ingest Lambda for SEASON (default 2025); fails unless ok is true
	@mkdir -p build
	aws lambda invoke \
		--function-name $(call lake_out,ingest_function_name) \
		--cli-binary-format raw-in-base64-out \
		--cli-read-timeout 310 \
		--payload '{"seasons": [$(SEASON)], "datasets": ["schedules", "player_week"]}' \
		build/ingest-response.json
	uv run python -c 'import json, sys; d = json.load(open("build/ingest-response.json")); print(json.dumps(d, indent=2)); sys.exit(0 if d.get("ok") else 1)'

build: lake-init ## dbt seed + dbt build (models, generic, unit and parity tests) on Athena
	$(DBT_ENV) $(DBT) seed $(DBT_ARGS)
	$(DBT_ENV) $(DBT) build $(DBT_ARGS)
	@$(MAKE) --no-print-directory scanned

test: lake-init ## dbt test against the tables already built (no rebuild)
	$(DBT_ENV) $(DBT) test $(DBT_ARGS)
	@$(MAKE) --no-print-directory scanned

scanned: ## Total Athena data scanned by the last dbt invocation (from run_results.json)
	@uv run python -c 'import json; r = json.load(open("transform/target/run_results.json"))["results"]; b = sum((x.get("adapter_response") or {}).get("data_scanned_in_bytes") or 0 for x in r); print(f"Athena scanned {b / 1e6:.1f} MB across {len(r)} nodes")'

cost: ## Last 30 days of cost: Project-tagged, and the whole account by service
	@start=$$(date -u -d '30 days ago' +%F); end=$$(date -u -d tomorrow +%F); \
	echo "Project=snapcount-lakehouse ($$start to $$end):"; \
	aws ce get-cost-and-usage --region us-east-1 --time-period Start=$$start,End=$$end \
		--granularity MONTHLY --metrics UnblendedCost \
		--filter '{"Tags": {"Key": "Project", "Values": ["snapcount-lakehouse"]}}' \
		--query 'ResultsByTime[].Total.UnblendedCost' --output table; \
	echo "Whole account, by service:"; \
	aws ce get-cost-and-usage --region us-east-1 --time-period Start=$$start,End=$$end \
		--granularity MONTHLY --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE \
		--query 'ResultsByTime[].Groups[].[Keys[0], Metrics.UnblendedCost.Amount]' --output table

down: lake-init ## Destroy the lake stack (data bucket emptied; state bucket kept)
	$(TF_LAKE) destroy
