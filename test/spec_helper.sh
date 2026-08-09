# shellcheck shell=sh
# Loaded into every spec via .shellspec (--require spec_helper).

spec_helper_configure() {
  : # minimum_version, before/after hooks land here as the suite grows
}

# The locale guard, for `Skip if`. In a single-byte locale the theme deliberately draws its
# ASCII register — different separators, marks and ellipses — so an example that pins the
# multibyte output is skipped there rather than failed: the difference is the design, not a
# defect. One copy here, because it is one rule.
inzsh_spec_bytes_not_cells() {
  local sample=é
  [ ${#sample} -ne 1 ]
}
