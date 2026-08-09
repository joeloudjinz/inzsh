SHELL := /bin/zsh
.DEFAULT_GOAL := help

SHELLSPEC ?= shellspec
PYTHON ?= ./.venv/bin/python
COLS ?= 80
SCALE ?= 1

.PHONY: help setup test test-ui test-install spec-guard perf grid play demo watch
.PHONY: golden-update golden-check bundle doctor shots

help: ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "  %-14s %s\n", $$1, $$2}'

setup: ## install the native toolchain
	@zsh tools/setup.zsh

test: ## everything runnable locally
	@zsh tools/spec-guard.zsh
	@$(SHELLSPEC) test/unit test/render
	@$(MAKE) --no-print-directory test-ui

# Skips rather than fails when the venv is absent, so `make test` still runs without it.
# CI builds the venv and runs this layer as its own `ui` job.
spec-guard: ## refuse a spec file that defines no examples
	@zsh tools/spec-guard.zsh

test-ui: ## L3 terminal-grid tests (pty + pyte); needs the python venv
	@if [[ -x $(PYTHON) ]]; then \
	  $(PYTHON) -m unittest discover -s test/ui -p 'test_*.py' -v; \
	else \
	  print -- "make test-ui: no python venv — run 'make setup' first (skipped)"; \
	fi

# Deliberately not part of `make test`: it is its own CI job, and CI is where it is
# authoritative. Runnable locally because every example builds its own HOME with `mktemp -d`
# — the real one is never read, written or backed up.
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

# Local generation only, by design: no CI job renders these. Each tape runs inside the
# pinned fixture environment (tools/tape-env.zsh); output lands in demo-out/, gitignored.
demo: ## render the VHS tapes to demo-out/ and publish the showcase (SCALE=2 for high-DPI)
	@for tape in test/tapes/*.tape; do \
	  [[ $${tape:t} == shot-* ]] && continue; \
	  SCALE=$(SCALE) zsh tools/tape-run.zsh $$tape; \
	done
	@cp demo-out/gifs/showcase.gif docs/assets/showcase.gif
	@print -- "demo: published docs/assets/showcase.gif"

# The stills the readme shows, and the one command that rebuilds them. `shots` writes into
# docs/assets directly — what is committed is what the tape drew.
shots: ## regenerate the README screenshots from fixtures into docs/assets (SCALE=2 for high-DPI)
	@for s in sharp warm 256 salah; do \
	  SCALE=$(SCALE) zsh tools/tape-run.zsh test/tapes/shot-$$s.tape; \
	  ffmpeg -y -loglevel error -i demo-out/shot-$$s.gif -filter_complex "[0]reverse[r]" \
	    -map "[r]" -frames:v 1 docs/assets/shot-$$s.png; \
	done
	@print -- "shots: docs/assets/shot-{sharp,warm,256,salah}.png"

watch: ## re-render on save
	@echo "make watch: not implemented — use 'make shots' or 'make demo' to rebuild captures"

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
