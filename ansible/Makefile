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
	# ansible-galaxy install -r requirements/roles.yml

.PHONY: check-linode-env-token
check-linode-env-token:
	@if [ ! -f .env ]; then \
		echo "Error: .env file not found. Please ensure .env file exists in the current directory."; \
		exit 1; \
	fi
	$(eval export $(shell cat .env | grep -v '^#' | sed 's/=.*//' | xargs))
	@if [ -z "$${LINODE_API_TOKEN}" ]; then \
		echo "Error: LINODE_API_TOKEN is undefined. Please set it in .env file or export it as an environment variable."; \
		exit 1; \
	fi

.PHONY: inventory
inventory: check-linode-env-token
	ansible-inventory -i inventory --graph -v

