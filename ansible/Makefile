SHELL := /bin/bash
.DEFAULT_GOAL := help

# Virtual environment
VENV := .venv

# Use uv if available, fallback to pip
UV := $(shell command -v uv 2>/dev/null)
ifdef UV
    PIP := uv pip
else
    PIP := $(VENV)/bin/pip
endif

.PHONY: help
help: ## Show this help
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
	@echo ""
	@echo "LOCAL DEVELOPMENT WORKFLOW:"
	@echo "  1. make install                     # Install ansible + deps in venv"
	@echo "  2. source $(VENV)/bin/activate      # Activate venv"
	@echo "  3. make test                        # Test connection"
	@echo "  4. ansible-playbook ...             # Run playbooks"
	@echo ""
	@echo "CI/GitHub Actions use system ansible + composite actions"

$(VENV): ## Create virtual environment
ifdef UV
	uv venv $(VENV)
else
	python3 -m venv $(VENV)
endif

.PHONY: install
install: $(VENV) ## Install ansible and dependencies (local development only)
ifdef UV
	cd $(VENV) && $(PIP) install -r ../requirements/requirements.txt -r ../requirements/requirements-local.txt
else
	$(PIP) install -r requirements/requirements.txt -r requirements/requirements-local.txt
endif
	$(VENV)/bin/ansible-galaxy collection install -r requirements/collections.yml --collections-path $(VENV)/lib/python*/site-packages/ansible_collections
	$(VENV)/bin/ansible-galaxy role install -r requirements/roles.yml --roles-path $(VENV)/share/ansible/roles

.PHONY: clean
clean: ## Remove virtual environment
	rm -rf $(VENV)

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
