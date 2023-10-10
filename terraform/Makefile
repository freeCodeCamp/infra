SHELL := /bin/bash

# Dynamically get all directories (stacks) in the current directory, excluding those starting with '__'
STACKS := $(shell find . -maxdepth 1 -mindepth 1 -type d -not -name '__*' -exec basename {} \;)

.PHONY: all upgrade fmt help $(STACKS)

all: help

help:
	@echo ""
	@echo "Available tasks:"
	@echo ""
	@echo "  make upgrade    Run terraform init -upgrade and terraform plan on all stacks"
	@echo "  make fmt        Run terraform fmt on all stacks"
	@echo "  make help       Display this help message"
	@echo ""
	@echo "Stacks are:"
	@echo ""
	@for stack in $(STACKS); do \
		echo " $$stack"; \
	done

upgrade:
	@if [ "$(filter-out $@,$(MAKECMDGOALS))" != "" ]; then \
		stack=$(filter-out $@,$(MAKECMDGOALS)); \
		echo ""; \
		echo ">>> Processing stack: $$stack <<<"; \
		echo ""; \
		cd $$stack && terraform init -upgrade && terraform plan && cd ..; \
	else \
		for stack in $(STACKS); do \
			echo ""; \
			echo ">>> Processing stack: $$stack <<<"; \
			echo ""; \
			cd $$stack && terraform init -upgrade && terraform plan && cd ..; \
		done \
	fi

fmt:
	@if [ "$(filter-out $@,$(MAKECMDGOALS))" != "" ]; then \
		stack=$(filter-out $@,$(MAKECMDGOALS)); \
		echo ""; \
		echo ">>> Formatting stack: $$stack <<<"; \
		echo ""; \
		cd $$stack && terraform fmt && cd ..; \
	else \
		for stack in $(STACKS); do \
			echo ""; \
			echo ">>> Formatting stack: $$stack <<<"; \
			echo ""; \
			cd $$stack && terraform fmt && cd ..; \
		done \
	fi
