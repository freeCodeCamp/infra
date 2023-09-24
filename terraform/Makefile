SHELL := /bin/bash

# Dynamically get all directories (stacks) in the current directory, excluding those starting with '__'
STACKS := $(shell find . -maxdepth 1 -mindepth 1 -type d -not -name '__*' -exec basename {} \;)

.PHONY: all $(STACKS)

all: $(STACKS)

$(STACKS):
	@echo ""
	@echo ">>> Processing stack: $@ <<<"
	@echo ""
	@CURRENT_DIR=$(shell pwd) && \
	cd $@ && \
	terraform init -upgrade && \
	terraform plan && \
	cd $$CURRENT_DIR

