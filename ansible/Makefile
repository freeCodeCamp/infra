SHELL := /bin/bash

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Usage: make [Target] [Environment Variables]"
	@echo ""
	@echo "Targets:"
	@echo "  help             Show this help message"
	@echo "  install          Install ansible and ansible-lint"


.PHONY: install
install:
	pip install -r requirements/requirements.txt
	ansible-galaxy collection install -r requirements/collections.yml
	# ansible-galaxy install -r requirements/roles.yml

.PHONY: check-linode-env-token
check-linode-env-token:
ifndef LINODE_API_TOKEN
  include ./.env
  export $(shell sed 's/=.*//' .env)
endif

.PHONY: check-linode-env-token
check-linode-env-token:
ifndef LINODE_API_TOKEN
	$(error LINODE_API_TOKEN is undefined. Please set it in .env file or export it as an environment variable.)
endif

.PHONY: inventory
inventory: check-linode-env-token
	ansible-inventory -i inventory --graph -v
