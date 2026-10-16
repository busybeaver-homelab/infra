#!/usr/bin/env bats
# Meta-tests for Bats test suite hygiene and Bash >= 4 enforcement (REV2-P3-7 / R2-GATE-05)

load 'helpers/test_helper'

@test "test_helper.bash requires Bats >= 1.5.0 and fails fast on Bash < 4" {
  local helper="$REPO_ROOT/tests/scripts/helpers/test_helper.bash"
  run grep -F "bats_require_minimum_version 1.5.0" "$helper"
  [ "$status" -eq 0 ]

  run grep -F "BASH_VERSINFO[0] < 4" "$helper"
  [ "$status" -eq 0 ]
}

@test "all Bats test files load helpers/test_helper or enforce strict assertions" {
  local missing=0
  for f in "$REPO_ROOT"/tests/scripts/*.bats; do
    if ! grep -qE "load ['\"]helpers/test_helper['\"]" "$f"; then
      echo "Missing load 'helpers/test_helper' in $(basename "$f")" >&2
      missing=$((missing + 1))
    fi
  done
  [ "$missing" -eq 0 ]
}

@test "no Bats test file contains a non-final bare [[ ... ]] assertion without || false" {
  run awk '
    FNR == 1 { pending = ""; delim = "" }
    delim != "" {
      t = $0
      sub(/^[[:space:]]+/, "", t)
      sub(/[[:space:]]+$/, "", t)
      if (t == delim) delim = ""
      next
    }
    $0 ~ /^[[:space:]]*(#.*)?$/ { next }
    {
      if (pending != "") {
        if ($0 !~ /^[[:space:]]*(}|done([[:space:]].*)?)[[:space:]]*$/) print pending
        pending = ""
      }
      if ($0 ~ /^[[:space:]]+\[\[ .* \]\][[:space:]]*$/) pending = FILENAME ":" FNR
      if (match($0, /<<-?[[:space:]]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/) &&
        !(RSTART > 1 && substr($0, RSTART - 1, 1) == "<")) {
        d = substr($0, RSTART, RLENGTH)
        sub(/^<<-?[[:space:]]*/, "", d)
        gsub(/["\047]/, "", d)
        delim = d
      }
    }
  ' "$REPO_ROOT"/tests/scripts/*.bats
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
