SHELL := /bin/zsh
.DEFAULT_GOAL := help

SHELLSPEC ?= shellspec
PYTHON ?= ./.venv/bin/python
COLS ?= 80

.PHONY: help setup test test-ui render grid demo watch golden-update bundle doctor

help: ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "  %-14s %s\n", $$1, $$2}'

setup: ## install the native toolchain
	@zsh tools/setup.zsh

test: ## everything runnable locally
	@$(SHELLSPEC) test/unit test/render
	@$(MAKE) --no-print-directory test-ui

# Skips rather than fails when the venv is absent — CI doesn't build one yet, and
# wiring L3 into CI happens with the M1 gate.
test-ui: ## L3 terminal-grid tests (pty + pyte); needs the python venv
	@if [[ -x $(PYTHON) ]]; then \
	  $(PYTHON) -m unittest discover -s test/ui -p 'test_*.py' -v; \
	else \
	  print -- "make test-ui: no python venv — run 'make setup' first (skipped)"; \
	fi

render: ## print the prompt as it currently is
	@echo "make render: nothing to render yet — the token layer lands at M1"

grid: ## rendered terminal grid, per-cell colours (default COLS=80)
	@echo "make grid: the L3 pyte runner lands at M1"

demo: ## VHS visual render
	@echo "make demo: tapes land at M8"

watch: ## re-render on save
	@echo "make watch: nothing to watch yet — the token layer lands at M1"

golden-update: ## regenerate golden files deliberately
	@echo "make golden-update: the golden pipeline lands at M8"

bundle: ## concatenate into a single distributable file
	@echo "make bundle: the manifest lands with the engine at M2"

doctor: ## environment diagnostic, same code path as the shipped command
	@echo "make doctor: ships at M8"
