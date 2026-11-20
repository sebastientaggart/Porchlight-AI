# Front door. Every target is a thin wrapper around scripts/, which also run
# without make (Unraid doesn't ship it). Plan: docs/plans/makefile.md.
#
# Missing values are asked for; pass them to skip the questions, e.g.
#   make set-budget KID=alex USD=10

.DEFAULT_GOAL := help
.PHONY: help review audit spending budget open add-kid set-budget set-models doctor up down logs backup

help: ## Show this list
	@awk 'BEGIN {FS = ":.*## "} \
	  /^##@/ {printf "\n%s\n", substr($$0, 5)} \
	  /^[a-z][a-z -]*:.*## / {t = $$1; gsub(/ /, ", ", t); printf "  make %-20s %s\n", t, $$2}' $(MAKEFILE_LIST)
	@echo

##@ Daily

review audit: ## What the kids said: the audit log. Optional: KID=alex N=50
	@./scripts/review-logs.sh "$(or $(N),20)" "$(KID)"

spending budget: ## Spend and budget per key this period, and the last 7 days
	@./scripts/spending.sh

open: ## Open the chat app and the LiteLLM admin UI
	@./scripts/open.sh

##@ Kids

add-kid: ## Add a kid: key, connection, restart, then the UI checklist
	@./scripts/add-kid.sh "$(KID)" "$(BIRTHDATE)" "$(USD)" "$(MODELS)"

set-budget: ## Change a kid's monthly budget (KID=, USD=)
	@./scripts/set-kid-budget.sh "$(KID)" "$(USD)"

set-models: ## Change a kid's models (KID=, MODELS=claude-kids,claude-kids-plus)
	@./scripts/set-kid-models.sh "$(KID)" "$(MODELS)"

##@ Maintenance

doctor: ## Check the whole setup and say what's wrong
	@./scripts/doctor.sh

up: ## Start (or apply .env and compose changes)
	@docker compose up -d --wait

down: ## Stop (data is kept)
	@docker compose down

logs: ## Follow container logs. Optional: S=litellm
	@docker compose logs -f --tail 50 $(S)

backup: ## Back up the audit log and Open WebUI's database to backups/
	@./scripts/backup.sh
