#!/usr/bin/env bats
# Guards for the living status register of the infrastructure review 2 roadmap.
# The plan (Part D) defines the REV2-P* tasks; the register records their current state.

load 'helpers/test_helper'

PLAN="${REPO_ROOT}/docs/plans/2026-10-13-infrastructure-review-2-improvement-plan.md"
REGISTER="${REPO_ROOT}/docs/plans/2026-10-13-infrastructure-review-2-status.md"
STATUSES=("Done" "In Progress" "Partial" "Open" "Owner" "Superseded" "N/A")
STATUSES_PIPE="Done|In Progress|Partial|Open|Owner|Superseded|N/A"

setup() {
  # Both files live under docs/** and are git-crypt ciphertext without the key (e.g. in CI).
  for f in "$PLAN" "$REGISTER"; do
    [ -f "$f" ] || { echo "missing: $f" >&2; return 1; }
    if is_git_crypt_encrypted "$f"; then
      skip "review plan/register are git-crypt encrypted in this checkout"
    fi
  done
}

# Prints "<id>|<status>|<pr>|<gap>" for every register row whose first cell is a REV2 ID.
register_rows() {
  awk -F'|' '$2 ~ /^ *REV2-/ {
    for (i = 2; i <= 7; i++) gsub(/^ +| +$/, "", $i)
    print $2 "|" $3 "|" $5 "|" $7
  }' "$REGISTER"
}

@test "every roadmap task in the plan appears exactly once in the register" {
  local missing=0 id count
  while IFS= read -r id; do
    count="$(register_rows | awk -F'|' -v id="$id" '$1 == id' | wc -l | tr -d ' ')"
    if [ "$count" != "1" ]; then
      echo "${id}: ${count} register rows" >&2
      missing=1
    fi
  done < <(grep -oE '^\| REV2-P[0-9]+-[0-9]+ ' "$PLAN" | tr -d '| ')
  [ "$missing" -eq 0 ]
}

@test "the register has no roadmap IDs that the plan does not define" {
  local unknown=0 id
  while IFS= read -r id; do
    if [[ "$id" == REV2-P* ]] && ! grep -qE "^\| ${id} " "$PLAN"; then
      echo "unknown roadmap task: ${id}" >&2
      unknown=1
    fi
    # Items found after the review use REV2-X-<n>; anything else is a typo.
    if [[ "$id" != REV2-P* && ! "$id" =~ ^REV2-X-[0-9]+$ ]]; then
      echo "invalid ID: ${id}" >&2
      unknown=1
    fi
  done < <(register_rows | cut -d'|' -f1)
  [ "$unknown" -eq 0 ]
}

@test "every register row uses an allowed status" {
  local bad=0 id status
  while IFS='|' read -r id status _; do
    if [[ "|${STATUSES_PIPE}|" != *"|${status}|"* ]]; then
      echo "${id}: invalid status '${status}'" >&2
      bad=1
    fi
  done < <(register_rows)
  [ "$bad" -eq 0 ]
}

@test "Done rows cite a PR or commit; unfinished rows name the remaining gap" {
  local bad=0 id status pr gap
  while IFS='|' read -r id status pr gap; do
    if [ "$status" = "Done" ] && [[ ! "$pr" =~ (\#[0-9]+|[0-9a-f]{7,40}) ]]; then
      echo "${id}: Done without PR/SHA" >&2
      bad=1
    fi
    if [[ "$status" =~ ^(In\ Progress|Partial|Open|Owner)$ ]] && [[ -z "$gap" || "$gap" == "-" || "$gap" == "—" ]]; then
      echo "${id}: ${status} without a remaining gap" >&2
      bad=1
    fi
  done < <(register_rows)
  [ "$bad" -eq 0 ]
}

@test "the summary table matches the register rows" {
  local bad=0 phase status expected actual
  for phase in P0 P1 P2 P3 P4 X; do
    for status in "${STATUSES[@]}"; do
      actual="$(register_rows | awk -F'|' -v p="REV2-${phase}-" -v s="$status" 'index($1, p) == 1 && $2 == s' | wc -l | tr -d ' ')"
      # Summary row: | P0 | <Done> | <In Progress> | <Partial> | <Open> | <Owner> | <Superseded> | <N/A> | <Total> |
      expected="$(awk -F'|' -v p="$phase" -v s="$status" -v sp="$STATUSES_PIPE" '
        BEGIN { n = split(sp, cols, "|") }
        { gsub(/ /, "", $2) }
        $2 == p { for (i = 1; i <= n; i++) if (cols[i] == s) { v = $(i + 2); gsub(/ /, "", v); print v } }' "$REGISTER")"
      if [ "${expected:-missing}" != "$actual" ]; then
        echo "summary ${phase}/${status}: table says ${expected:-missing}, rows say ${actual}" >&2
        bad=1
      fi
    done
  done
  [ "$bad" -eq 0 ]
}

@test "the plan points readers to the register" {
  run grep -F "2026-10-13-infrastructure-review-2-status.md" "$PLAN"
  [ "$status" -eq 0 ]
}
