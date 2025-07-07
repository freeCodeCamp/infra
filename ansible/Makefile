SHELL := /bin/bash
.DEFAULT_GOAL := help

# Virtual environment
VENV := .venv
ANSIBLE := $(VENV)/bin/ansible

# Use uv if available, fallback to pip
UV := $(shell command -v uv 2>/dev/null)
ifdef UV
    PIP := uv pip
else
    PIP := $(VENV)/bin/pip
endif

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "%-15s %s\n", $$1, $$2}'

$(VENV): ## Create virtual environment
ifdef UV
	uv venv $(VENV)
else
	python3 -m venv $(VENV)
endif

.PHONY: install
install: $(VENV) ## Install dependencies
ifdef UV
	cd $(VENV) && $(PIP) install -r ../requirements/requirements.txt
else
	$(PIP) install -r requirements/requirements.txt
endif
	$(ANSIBLE)-galaxy collection install -r requirements/collections.yml
	$(ANSIBLE)-galaxy role install -r requirements/roles.yml


.PHONY: inventory
inventory: $(VENV) ## Show inventory graph
	$(ANSIBLE)-inventory -i inventory --graph -v


.PHONY: clean
clean: ## Remove virtual environment
	rm -rf $(VENV)

.PHONY: activate
activate: $(VENV) ## Show activation command
	@echo "To activate the virtual environment, run:"
	@echo "source $(VENV)/bin/activate"
