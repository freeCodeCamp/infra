SHELL := /bin/bash

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Usage: make [Target] [Environment Variables]"
	@echo ""
	@echo "Targets:"
	@echo "  help             Show this help message"
	@echo "  install          Install ansible and ansible-lint"
	@echo "  inventory        Generate inventory graph"

.PHONY: install
install:
	pip install -r requirements/requirements.txt
	ansible-galaxy collection install -r requirements/collections.yml
	ansible-galaxy role install -r requirements/roles.yml

.PHONY: check-env-keys
check-env-keys:
	@if [ ! -f .env ]; then \
		echo "Error: .env file not found. Please ensure .env file exists in the current directory."; \
		exit 1; \
	fi

.PHONY: inventory
inventory: check-env-keys
	ansible-inventory -i inventory --graph -v

