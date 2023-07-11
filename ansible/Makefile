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
	ansible-galaxy install -r requirements.yml --pre

.PHONY: check-linode-token
check-linode-token:
  ifndef LINODE_API_TOKEN
    $(error LINODE_API_TOKEN is undefined)
  endif

.PHONY: check-az-pat
check-az-pat:
  ifndef AZURE_DEVOPS_PAT
    $(error AZURE_DEVOPS_PAT is undefined)
  endif

.PHONY: inventory
inventory: check-linode-token
	ansible-inventory -i inventory --graph -vvv

.PHONY: install-az-agent
install-az-agent: check-az-pat
  ansible-playbook play-oldeworld--azops-1-install.yml -v
