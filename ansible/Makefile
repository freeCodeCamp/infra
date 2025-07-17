SHELL := /bin/bash
.DEFAULT_GOAL := help

# Virtual environment
VENV := .venv

.PHONY: help
help: ## Show this help
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
	@echo ""
	@echo "UV-BASED WORKFLOW:"
	@echo "  1. make install                     # Install ansible + deps with uv"
	@echo "  2. source $(VENV)/bin/activate      # Activate venv"
	@echo "  3. make test                        # Test connection"
	@echo "  4. ansible-playbook ...             # Run playbooks"

.PHONY: install
install: ## Install ansible and dependencies using uv
	@if ! command -v uv >/dev/null 2>&1; then \
		echo "ERROR: uv not found. Please install uv first:"; \
		echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"; \
		exit 1; \
	fi
	uv sync
	source $(VENV)/bin/activate && ansible-galaxy install -r requirements.yml

.PHONY: clean
clean: ## Remove virtual environment and ansible directories
	rm -rf $(VENV) .ansible

.PHONY: activate
activate: $(VENV) ## Show activation command
	@echo "To activate the virtual environment, run:"
	@echo "source $(VENV)/bin/activate"

.PHONY: test
test: ## Test connection to random VM (requires sourced venv, INVENTORY=linode.yml)
	@echo "Counting VMs in inventory..."
	@if ! command -v ansible >/dev/null 2>&1; then \
		echo "ERROR: ansible not found - did you source the venv?"; \
		echo "Run: source $(VENV)/bin/activate"; \
		exit 1; \
	fi
	@if ! command -v jq >/dev/null 2>&1; then \
		echo "ERROR: jq not found - please install jq"; \
		exit 1; \
	fi
	@VM_COUNT=$$(ansible-inventory -i inventory/$(INVENTORY) --list 2>/dev/null | jq -r '._meta.hostvars | keys | length'); \
	if [ $$? -ne 0 ]; then \
		echo "ERROR: Failed to parse inventory"; \
		exit 1; \
	fi; \
	echo "Found $$VM_COUNT VMs in inventory"; \
	if [ $$VM_COUNT -eq 0 ]; then \
		echo "ERROR: No VMs found in inventory"; \
		exit 1; \
	fi; \
	RANDOM_INDEX=$$(( RANDOM % $$VM_COUNT )); \
	echo "Testing connection to VM at index $$RANDOM_INDEX..."; \
	if ! ansible -i inventory/$(INVENTORY) all[$$RANDOM_INDEX] -m ping --one-line -v; then \
		echo "ERROR: Connection test failed"; \
		exit 1; \
	fi; \
	echo "SUCCESS: Connection test passed"

# Set default inventory
INVENTORY ?= linode.yml
