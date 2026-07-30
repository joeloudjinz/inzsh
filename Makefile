SHELL := /bin/zsh
.DEFAULT_GOAL := help

SHELLSPEC ?= shellspec
PYTHON ?= ./.venv/bin/python
COLS ?= 80

.PHONY: help setup test test-ui spec-guard perf render render-matrix grid demo watch
.PHONY: golden-update bundle doctor

help: ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "  %-14s %s\n", $$1, $$2}'

setup: ## install the native toolchain
	@zsh tools/setup.zsh

test: ## everything runnable locally
	@zsh tools/spec-guard.zsh
	@$(SHELLSPEC) test/unit test/render
	@$(MAKE) --no-print-directory test-ui

# Skips rather than fails when the venv is absent — CI doesn't build one yet, and
# wiring L3 into CI happens with the M1 gate.
spec-guard: ## refuse a spec file that defines no examples
	@zsh tools/spec-guard.zsh

test-ui: ## L3 terminal-grid tests (pty + pyte); needs the python venv
	@if [[ -x $(PYTHON) ]]; then \
	  $(PYTHON) -m unittest discover -s test/ui -p 'test_*.py' -v; \
	else \
	  print -- "make test-ui: no python venv — run 'make setup' first (skipped)"; \
	fi

# Deliberately not part of `make test`: a benchmark on a laptop that is compiling something
# else measures the something else. It is its own target and its own CI job, and the CI job is
# where a breach is a verdict. `zsh -f` for the same reason every other harness uses it — the
# suite must not measure somebody's zshrc.
perf: ## render budget benchmarks, gated against declared budgets
	@zsh -f test/perf/bench.zsh

# The M1 demonstration prompt, not the engine — there are no segments yet. Always a subshell:
# work in progress is never sourced into the shell you are typing into.
render: ## print the prompt as it currently is (INZSH_PRESET/_COLOR_DEPTH/_SURFACE_MODE)
	@zsh -f tools/render.zsh

render-matrix: ## both presets at all three colour depths, to stdout and render-out/
	@zsh -f tools/render-matrix.zsh

grid: ## rendered terminal grid, per-cell colours (default COLS=80); needs the python venv
	@if [[ -x $(PYTHON) ]]; then \
	  $(PYTHON) tools/grid.py --cols $(COLS); \
	else \
	  print -- "make grid: no python venv — run 'make setup' first (skipped)"; \
	fi

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
