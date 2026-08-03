#!/usr/bin/env zsh
# InZsh — the `make doctor` launcher. The same code path as the shipped command: the block is
# printed by the `inzsh doctor` that `lib/core/doctor.zsh` defines, never re-implemented here.
#
# Run it, never source it into a live shell:
#
#   zsh -f tools/doctor.zsh
#
# The theme file itself is not sourced: it no-ops in a non-interactive shell, which is exactly
# what this is. The files below are the ones the doctor reads through — detection, the guard
# registry, and the salah library whose location provenance it reports — in the entry point's
# own order.

_inzsh_doctor_root=${${(%):-%x}:A:h:h}

source $_inzsh_doctor_root/lib/core/config.zsh
source $_inzsh_doctor_root/lib/core/detect.zsh

source $_inzsh_doctor_root/lib/salah/calc.zsh
source $_inzsh_doctor_root/lib/salah/methods.zsh
source $_inzsh_doctor_root/lib/salah/cache.zsh
source $_inzsh_doctor_root/lib/salah/location.zsh

source $_inzsh_doctor_root/lib/core/doctor.zsh

_inzsh_config_absorb_all

inzsh doctor
