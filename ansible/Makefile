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
	pip install ansible ansible-lint
	pip install -r requirements.txt
	ansible-galaxy install -r requirements.yml

.PHONY: check-inventory
check-inventory:
	ansible-inventory -i inventory --graph
