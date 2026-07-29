SHELL := /bin/zsh
.DEFAULT_GOAL := help

SHELLSPEC ?= shellspec
COLS ?= 80

.PHONY: help setup test render grid demo watch golden-update bundle doctor

help: ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "  %-14s %s\n", $$1, $$2}'

setup: ## install the native toolchain
	@zsh tools/setup.zsh

test: ## everything runnable locally
	@$(SHELLSPEC) test/unit test/render

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
