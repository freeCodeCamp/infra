# freeCodeCamp API Stack Deployment Makefile

.PHONY: help validate decrypt config debug deploy clean

# Default target
help:
	@echo "freeCodeCamp API Stack Deployment"
	@echo ""
	@echo "Available targets:"
	@echo "  validate   Validate all required environment variables"
	@echo "  decrypt    Decrypt age-encrypted secrets (requires AGE_* vars)"
	@echo "  config     Validate Docker stack configuration"
	@echo "  debug      Save stack configuration to debug file"
	@echo "  deploy     Deploy stack (auto-detects dev/prod from DEPLOYMENT_TLD)"
	@echo "  clean      Remove temporary files"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - Set DEPLOYMENT_VERSION and DEPLOYMENT_TLD environment variables"
	@echo "  - For encrypted secrets: run 'make decrypt' first"
	@echo "  - For manual deployment: source variables from .env or export manually"

# Validate environment variables
validate:
	@echo "Validating environment variables..."
	@./scripts/validate-env.sh

# Decrypt age-encrypted secrets
decrypt:
	@echo "Decrypting secrets..."
	@./scripts/decrypt-secrets.sh --save-env

# Validate Docker stack configuration
config:
	@echo "Validating Docker stack configuration..."
	@docker stack config -c stack-api.yml > /dev/null
	@echo "Stack configuration is valid"

# Save debug configuration
debug:
	@echo "Generating debug configuration..."
	@if [ -z "$(DEPLOYMENT_VERSION)" ]; then \
		echo "ERROR: DEPLOYMENT_VERSION is required"; \
		exit 1; \
	fi
	@docker stack config -c stack-api.yml > debug-docker-stack-config-$(DEPLOYMENT_VERSION).yml
	@echo "Debug configuration saved to debug-docker-stack-config-$(DEPLOYMENT_VERSION).yml"

# Deploy stack (auto-detects environment from DEPLOYMENT_TLD)
deploy: validate config
	@echo "Deploying API stack..."
	@if [ "$(DEPLOYMENT_TLD)" = "dev" ]; then \
		echo "Deploying to staging environment..."; \
		docker stack deploy -c stack-api.yml --prune --with-registry-auth --detach=false stg-api; \
		echo "Successfully deployed stg-api stack"; \
	elif [ "$(DEPLOYMENT_TLD)" = "org" ]; then \
		echo "Deploying to production environment..."; \
		docker stack deploy -c stack-api.yml --prune --with-registry-auth --detach=false prd-api; \
		echo "Successfully deployed prd-api stack"; \
	else \
		echo "ERROR: DEPLOYMENT_TLD must be 'dev' or 'org'"; \
		exit 1; \
	fi

# Clean up temporary files
clean:
	@echo "Cleaning up temporary files..."
	@rm -f .env debug-docker-stack-config-*.yml
	@echo "Cleanup complete"