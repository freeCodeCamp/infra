SHELL := /bin/bash

# Base directory for Terraform stacks
TERRAFORM_BASE_DIR := .

# Dynamically get all directories (stacks) in the TERRAFORM_BASE_DIR directory, excluding those starting with '__'
STACKS := $(shell find $(TERRAFORM_BASE_DIR)/ -maxdepth 1 -mindepth 1 -type d -not -name '__*' -exec basename {} \;)

.PHONY: all list upgrade fmt help

all: help

help:
	@echo ""
	@echo "Available tasks:"
	@echo ""
	@echo "  make list       List the available stacks"
	@echo "  make upgrade    Run terraform init -upgrade and terraform plan on all stacks"
	@echo "                  Use STACK=stack-name make upgrade, to process a given stack "
	@echo "  make fmt        Run terraform fmt on all stacks"
	@echo "                  Use STACK=stack-name make fmt, to process a given stack "
	@echo "  make help       Display this help message"
	@echo ""

list:
	@echo "Stacks are:"
	@echo ""
	@for stack in $(STACKS); do \
	  echo " $$stack"; \
	done

upgrade:
	@if [ -n "$(STACK)" ]; then \
	  echo ""; \
	  echo ">>> Processing stack: $(STACK) <<<"; \
	  echo ""; \
	  (cd $(TERRAFORM_BASE_DIR)/$(STACK) && terraform init -upgrade && terraform plan); \
	else \
	  for stack in $(STACKS); do \
	    echo ""; \
	    echo ">>> Processing stack: $$stack <<<"; \
	    echo ""; \
	    (cd $(TERRAFORM_BASE_DIR)/$$stack && terraform init -upgrade && terraform plan); \
	  done \
	fi

fmt:
	@if [ -n "$(STACK)" ]; then \
	  echo ""; \
	  echo ">>> Formatting stack: $(STACK) <<<"; \
	  echo ""; \
	  (cd $(TERRAFORM_BASE_DIR)/$(STACK) && terraform fmt); \
	else \
	  for stack in $(STACKS); do \
	    echo ""; \
	    echo ">>> Formatting stack: $$stack <<<"; \
	    echo ""; \
	    (cd $(TERRAFORM_BASE_DIR)/$$stack && terraform fmt); \
	  done \
	fi

