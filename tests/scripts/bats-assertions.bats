#!/usr/bin/env bats
# Guards against [[ ]] assertions that macOS /bin/bash 3.2 silently ignores.
#
# On bash 3.2, errexit does not fire on a failing [[ ]], so a bare [[ ]] that is not
# the last command of a test can never fail it (bash >= 4.1 in CI is unaffected).
# Such assertions must end in `|| false`.

load 'helpers/test_helper'

# Prints <file>:<line> for every bare [[ ]] that is followed by another command in
# the same block. Heredoc bodies, blank lines and comments are ignored.
find_ineffective_assertions() {
  awk '
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
        if ($0 !~ /^[[:space:]]*}[[:space:]]*$/) print pending
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
  ' "$@"
}

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "flags a bare [[ ]] that is followed by another command" {
  cat <<'EOF' >"${BATS_TMPDIR}/sample.bats"
@test "sample" {
  run true
  [[ "$output" == "x" ]]
  [ "$status" -eq 0 ]
}
EOF

  run find_ineffective_assertions "${BATS_TMPDIR}/sample.bats"
  [ "$status" -eq 0 ]
  [ "$output" = "${BATS_TMPDIR}/sample.bats:3" ]
}

@test "accepts a final [[ ]], an [[ ]] ending in || false, and trailing comments" {
  cat <<'EOF' >"${BATS_TMPDIR}/sample.bats"
@test "final" {
  run true
  [[ "$output" == "" ]]
}

@test "guarded" {
  [[ "a" == "a" ]] || false
  [ 1 -eq 1 ]
}

@test "comment before close" {
  [[ "a" == "a" ]]
  # trailing note

}
EOF

  run find_ineffective_assertions "${BATS_TMPDIR}/sample.bats"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ignores [[ ]] inside heredoc bodies, including <<- with an indented delimiter" {
  cat <<'OUTER' >"${BATS_TMPDIR}/sample.bats"
@test "generates a script" {
  cat <<'EOF' >script.sh
  [[ -n "$1" ]]
  echo done
EOF
  cat <<-INNER >other.sh
	[[ -z "$2" ]]
	echo done
	INNER
  run bash script.sh
}
OUTER

  run find_ineffective_assertions "${BATS_TMPDIR}/sample.bats"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "does not mistake a here-string for a heredoc" {
  cat <<'EOF' >"${BATS_TMPDIR}/sample.bats"
@test "here-string" {
  grep -q x <<<word
  [[ "a" == "b" ]]
  [ 1 -eq 1 ]
}
EOF

  run find_ineffective_assertions "${BATS_TMPDIR}/sample.bats"
  [ "$status" -eq 0 ]
  [ "$output" = "${BATS_TMPDIR}/sample.bats:3" ]
}

@test "no bats file contains a [[ ]] assertion that bash 3.2 would ignore" {
  local files=()
  while IFS= read -r f; do
    files+=("${REPO_ROOT}/${f}")
  done < <(git -C "${REPO_ROOT}" ls-files -- '*.bats')
  [ "${#files[@]}" -gt 0 ]

  run find_ineffective_assertions "${files[@]}"
  [ "$status" -eq 0 ]
  if [ -n "$output" ]; then
    echo "Append '|| false' to these non-final [[ ]] assertions:" >&2
    echo "$output" >&2
    return 1
  fi
}
