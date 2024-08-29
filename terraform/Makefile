# Find all directories containing .terraform.lock.hcl files
WORKSPACES := $(shell find . -name ".terraform.lock.hcl" -exec dirname {} \;)

.PHONY: all
all: help

.PHONY: help
help:
	@echo "Available tasks:"
	@echo "  format          - Format Terraform files in all workspaces"
	@echo "  list-workspaces - List all detected Terraform workspaces"
	@echo "  validate        - Validate Terraform configurations in all workspaces"
	@echo "  init            - Initialize Terraform in all workspaces"
	@echo "  init-upgrade    - Initialize and upgrade Terraform in all workspaces"
	@echo "  plan            - Run Terraform plan in all workspaces"
	@echo "  clean           - Remove Terraform cache files from all workspaces"
	@echo "  help            - Show this help message"

.PHONY: format
format:
	@echo "Formatting Terraform files in all workspaces..."
	@for workspace in $(WORKSPACES); do \
		echo "Formatting $$workspace"; \
		terraform -chdir=$$workspace fmt; \
	done
	@echo "Formatting complete."

.PHONY: list-workspaces
list-workspaces:
	@echo "Detected Terraform workspaces:"
	@for workspace in $(WORKSPACES); do \
		echo "  $$workspace"; \
	done

.PHONY: validate
validate:
	@echo "Validating Terraform configurations in all workspaces..."
	@for workspace in $(WORKSPACES); do \
		echo "Validating $$workspace"; \
		terraform -chdir=$$workspace validate; \
	done
	@echo "Validation complete."

.PHONY: init
init:
	@echo "Initializing Terraform in all workspaces..."
	@for workspace in $(WORKSPACES); do \
		echo "Initializing $$workspace"; \
		terraform -chdir=$$workspace init; \
	done
	@echo "Initialization complete."

.PHONY: init-upgrade
init-upgrade:
	@echo "Initializing and upgrading Terraform in all workspaces..."
	@for workspace in $(WORKSPACES); do \
		echo "Initializing and upgrading $$workspace"; \
		terraform -chdir=$$workspace init -upgrade; \
	done
	@echo "Initialization and upgrade complete."

.PHONY: plan
plan:
	@echo "Running Terraform plan in all workspaces..."
	@for workspace in $(WORKSPACES); do \
		echo "Planning $$workspace"; \
		terraform -chdir=$$workspace plan; \
	done
	@echo "Planning complete."

.PHONY: clean
clean:
	@echo "Cleaning Terraform cache files from all workspaces..."
	@for workspace in $(WORKSPACES); do \
		echo "Cleaning $$workspace"; \
		rm -rf $$workspace/.terraform $$workspace/*.tfstate* $$workspace/.terraform.lock.hcl; \
	done
	@echo "Cleaning complete."
