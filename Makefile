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
# where a breach is a verdict. `-f` for the same reason every other harness uses it — the suite
# must not measure somebody's zshrc. `-i` because the headline row calls `_inzsh_render`, which
# returns early in a shell that is not interactive: without it the row measures that early return
# and passes having drawn nothing. The suite refuses a non-interactive shell rather than trusting
# this line to carry the flag, and `< /dev/null` so an interactive shell never inherits a terminal
# that something else is reading.
perf: ## render budget benchmarks, gated against declared budgets
	@zsh -f -i test/perf/bench.zsh < /dev/null

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
# TWO RUNGS PER PUBLISHED RECORDING, BOTH REAL RENDERS. The project page embeds these GIFs,
# and an animated GIF cannot go through a site's image pipeline — that pipeline decodes one
# frame and re-encodes it as a still, so it can neither resize nor re-emit the animation. The
# only sizes a browser can be offered are the ones this repo has actually rendered. So each
# published recording is rendered at both scales rather than resampled from one: `<name>.gif`
# is the 2x file the readme's <img> points at, `<name>-1000.gif` the 1x rung beside it, named
# by its rendered width so a third rung later is an addition and nothing has to be renamed.
#
# `$(SCALE)` still applies to every OTHER tape — those go to demo-out/ for looking at, and
# one size is enough for that. The two published ones ignore it, because what they publish is
# fixed by what the page needs rather than by how the command was invoked.
demo: ## render the tapes to demo-out/ and publish both rungs of the two the docs embed
	@for tape in test/tapes/*.tape; do \
	  [[ $${tape:t} == shot-* ]] && continue; \
	  [[ $${tape:t} == showcase.tape || $${tape:t} == rows.tape ]] && continue; \
	  SCALE=$(SCALE) zsh tools/tape-run.zsh $$tape; \
	done
	@for r in showcase rows; do \
	  SCALE=1 zsh tools/tape-run.zsh test/tapes/$$r.tape; \
	  cp demo-out/gifs/$$r.gif docs/assets/$$r-1000.gif; \
	  SCALE=2 zsh tools/tape-run.zsh test/tapes/$$r.tape; \
	  cp demo-out/gifs/$$r.gif docs/assets/$$r.gif; \
	done
	@print -- "demo: published docs/assets/{showcase,rows}.gif and their -1000 rungs"

# The stills the readme shows, and the one command that rebuilds them. `shots` writes into
# docs/assets directly — what is committed is what the tape drew.
# Both rungs here too, for the reason above — the page serves these stills as well, and a
# repo that publishes one rung leaves the site to render the other, which is the drift the
# next refresh pays for. A still COULD be resampled safely, unlike a GIF; rendering it
# instead keeps one rule for every capture rather than one rule per file type.
#
# The 1x file keeps the bare name, because that is what the readme already points at, and
# the 2x rung carries its rendered width. That is the opposite way round from the recordings
# above, and it is not an inconsistency to tidy: in both cases the bare name is the one that
# was published first, and renaming either would break a document that already links it.
shots: ## regenerate the README screenshots from fixtures into docs/assets, both rungs
	@for s in sharp warm 256 salah rows; do \
	  SCALE=1 zsh tools/tape-run.zsh test/tapes/shot-$$s.tape; \
	  ffmpeg -y -loglevel error -i demo-out/shot-$$s.gif -filter_complex "[0]reverse[r]" \
	    -map "[r]" -frames:v 1 docs/assets/shot-$$s.png; \
	  SCALE=2 zsh tools/tape-run.zsh test/tapes/shot-$$s.tape; \
	  ffmpeg -y -loglevel error -i demo-out/shot-$$s.gif -filter_complex "[0]reverse[r]" \
	    -map "[r]" -frames:v 1 docs/assets/shot-$$s-2000.png; \
	done
	@print -- "shots: docs/assets/shot-{sharp,warm,256,salah,rows}{,-2000}.png"

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
