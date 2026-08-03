SHELL := /bin/zsh
.DEFAULT_GOAL := help

SHELLSPEC ?= shellspec
PYTHON ?= ./.venv/bin/python
COLS ?= 80

.PHONY: help setup test test-ui test-install spec-guard perf grid demo watch
.PHONY: golden-update golden-check bundle doctor

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

# Deliberately not part of `make test` either: CLAUDE.md calls the installer suite CI-only,
# and CI is where it is authoritative. Runnable locally because every example builds its own
# HOME with `mktemp -d` — the real one is never read, written or backed up.
test-install: ## installer suite against a throwaway HOME (never yours)
	@zsh tools/spec-guard.zsh test/install
	@$(SHELLSPEC) test/install

# Deliberately not part of `make test`: a benchmark on a laptop that is compiling something
# else measures the something else. It is its own target and its own CI job, and the CI job is
# where a breach is a verdict. `zsh -f` for the same reason every other harness uses it — the
# suite must not measure somebody's zshrc.
perf: ## render budget benchmarks, gated against declared budgets
	@zsh -f test/perf/bench.zsh

grid: ## the theme as a terminal grid, per-cell colours (default COLS=80); needs the python venv
	@if [[ -x $(PYTHON) ]]; then \
	  $(PYTHON) tools/grid.py --cols $(COLS); \
	else \
	  print -- "make grid: no python venv — run 'make setup' first (skipped)"; \
	fi

play: ## a live prompt in a throwaway shell — every knob takes effect as you type
	@zsh tools/play.zsh

demo: ## VHS visual render
	@echo "make demo: tapes land at M8"

watch: ## re-render on save
	@echo "make watch: nothing to watch yet — the token layer lands at M1"

# The golden pipeline. Both targets render the real theme against fixtures — a temp git
# repository, a pinned clock, pinned identity — through tools/golden.py and the L3 harness.
# `golden-update` is the ONLY sanctioned way to change test/golden (and it never writes
# under test/fixtures); `golden-check` is the gate, run locally and by the CI golden job.
# Deliberately not part of `make test`: like the installer suite it has its own CI job,
# and a gate that failed inside `make test` would bury its diff in the suite's noise.
# A missing venv FAILS rather than skips — both targets are deliberate invocations, and a
# gate that silently skipped would gate nothing.
golden-update: ## regenerate golden files deliberately (never touches test/fixtures)
	@if [[ -x $(PYTHON) ]]; then \
	  $(PYTHON) tools/golden.py --update; \
	else \
	  print -- "make golden-update: no python venv — run 'make setup' first"; exit 1; \
	fi

golden-check: ## fail when the prompt no longer matches test/golden
	@if [[ -x $(PYTHON) ]]; then \
	  $(PYTHON) tools/golden.py --check; \
	else \
	  print -- "make golden-check: no python venv — run 'make setup' first"; exit 1; \
	fi

bundle: ## concatenate into a single distributable file (dist/inzsh.zsh-theme)
	@zsh -f tools/bundle.zsh

doctor: ## environment diagnostic, same code path as the shipped command
	@zsh -f tools/doctor.zsh
