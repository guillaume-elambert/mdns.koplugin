.PHONY: sync-mdns setup help

SHELL := /bin/bash

# The git ref to fetch mdns.lua from. Override on the command line:
#   make sync-mdns MDNS_REF=v1.11.1
MDNS_REF ?= master

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

setup: ## Initialize submodule with sparse-checkout and create symlink
	@bash sync-mdns.sh $(MDNS_REF)

sync-mdns: ## Update submodule to MDNS_REF and re-verify sparse-checkout + symlink
	@bash sync-mdns.sh $(MDNS_REF)
