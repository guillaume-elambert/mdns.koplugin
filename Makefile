-include .env
export

.PHONY: setup sync-mdns package dev tag release clean help

SHELL := /bin/bash

# Default ref from .env or fallback
MDNS_REF ?= $(DEFAULT_REF)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

setup: ## Initialize submodule with sparse-checkout and create symlink
	@bash sync-mdns.sh $(MDNS_REF)

sync-mdns: ## Update submodule to MDNS_REF and re-verify sparse-checkout + symlink
	@bash sync-mdns.sh $(MDNS_REF)

package: ## Build release zip in dist/ with dereferenced symlinks
	@bash package.sh

dev: ## Build dev/test zip in dist/ (includes git commit hash in version)
	@bash package.sh --dev

tag: ## Create local git tag matching version in _meta.lua
	@bash package.sh --tag

release: ## Build archive, tag, and publish GitHub release via gh CLI
	@bash package.sh --release

clean: ## Remove build artifacts in dist/
	@rm -rf dist
