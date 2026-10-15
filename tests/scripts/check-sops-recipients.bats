#!/usr/bin/env bats
# Tests for scripts/check-sops-recipients.sh (R2-SEC-01 step 5: SOPS recipient allowlist).

load 'helpers/test_helper'

CHECK="${REPO_ROOT}/scripts/check-sops-recipients.sh"
AGE_ACTIVE_PROD="age1prodactive0000000000000000000000000000000000000000000000"
AGE_ACTIVE_CI="age1ciactive000000000000000000000000000000000000000000000000"
AGE_RETIRED="age1retired0000000000000000000000000000000000000000000000000"
AGE_UNKNOWN="age1unknown0000000000000000000000000000000000000000000000000"
PGP_ACTIVE="0123456789ABCDEF0123456789ABCDEF01234567"

# Writes a SOPS-shaped file (metadata only; the check never decrypts).
sops_file() {
  local path="$1"
  shift
  {
    echo "secret: ENC[AES256_GCM,data:AAAA,iv:BBBB,tag:CCCC,type:str]"
    echo "sops:"
    echo "  age:"
    local r
    for r in "$@"; do
      if [[ "$r" == age1* ]]; then
        printf '    - recipient: %s\n      enc: dummy\n' "$r"
      fi
    done
    echo "  pgp:"
    for r in "$@"; do
      if [[ "$r" != age1* ]]; then
        printf '    - fp: %s\n      enc: dummy\n' "$r"
      fi
    done
    echo "  version: 3.13.3"
  } >"$path"
}

setup() {
  TMP_REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${TMP_REPO}/secrets"
  cd "$TMP_REPO" || return 1
  git init -q
  git config user.email "test@example.invalid"
  git config user.name "test"
  cat >.sops.yaml <<EOF
creation_rules:
  - path_regex: ^secrets/credentials\.ci\.sops\.ya?ml$
    key_groups:
      - age:
          - ${AGE_ACTIVE_CI}
  - path_regex: ^secrets/credentials\.sops\.ya?ml$
    key_groups:
      - age:
          - ${AGE_ACTIVE_PROD}
        pgp:
          - ${PGP_ACTIVE}
EOF
  cat >.sops-recipients.allowlist <<EOF
# test allowlist
${AGE_ACTIVE_PROD} active prod
${PGP_ACTIVE} active prod
${AGE_RETIRED} retired prod
${AGE_ACTIVE_CI} active ci
EOF
  sops_file secrets/credentials.sops.yaml "$AGE_ACTIVE_PROD" "$PGP_ACTIVE"
  sops_file secrets/credentials.ci.sops.yaml "$AGE_ACTIVE_CI"
  git add -A
  git commit -q -m "initial"
}

check() {
  run env REPO_ROOT="$TMP_REPO" bash "$CHECK" "$@"
}

@test "the real repository passes, including every historical revision" {
  run env REPO_ROOT="$REPO_ROOT" bash "$CHECK" --history
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOPS recipients OK (current files and history)"* ]] || false
  # Not vacuous: both files have active recipients in the allowlist.
  [ "$(grep -cE ' active prod$' "${REPO_ROOT}/.sops-recipients.allowlist")" -ge 1 ]
  [ "$(grep -cE ' active ci$' "${REPO_ROOT}/.sops-recipients.allowlist")" -ge 1 ]
}

@test "matching active recipients pass" {
  check --history
  [ "$status" -eq 0 ]
}

@test "an unknown recipient in a current file fails" {
  sops_file secrets/credentials.sops.yaml "$AGE_ACTIVE_PROD" "$PGP_ACTIVE" "$AGE_UNKNOWN"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"credentials.sops.yaml is encrypted to a recipient that is not active for prod: age1unknown0…"* ]] || false
  # Only a prefix of the recipient is printed.
  [[ "$output" != *"$AGE_UNKNOWN"* ]] || false
}

@test "a retired recipient may not encrypt the current file" {
  sops_file secrets/credentials.sops.yaml "$AGE_ACTIVE_PROD" "$PGP_ACTIVE" "$AGE_RETIRED"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"not active for prod"* ]] || false
}

@test "a recipient active for ci is not allowed for prod" {
  sops_file secrets/credentials.sops.yaml "$AGE_ACTIVE_PROD" "$PGP_ACTIVE" "$AGE_ACTIVE_CI"
  check
  [ "$status" -eq 1 ]
}

@test "history: an unlisted recipient in an old revision fails only with --history" {
  sops_file secrets/credentials.ci.sops.yaml "$AGE_UNKNOWN"
  git commit -qam "leaky revision"
  sops_file secrets/credentials.ci.sops.yaml "$AGE_ACTIVE_CI"
  git commit -qam "fixed"
  check
  [ "$status" -eq 0 ]
  check --history
  [ "$status" -eq 1 ]
  [[ "$output" == *"credentials.ci.sops.yaml@"*"is encrypted to an unlisted recipient"* ]] || false
}

@test "history: retired recipients are accepted in old revisions" {
  sops_file secrets/credentials.sops.yaml "$AGE_RETIRED" "$PGP_ACTIVE"
  git commit -qam "old key"
  sops_file secrets/credentials.sops.yaml "$AGE_ACTIVE_PROD" "$PGP_ACTIVE"
  git commit -qam "rotated"
  check --history
  [ "$status" -eq 0 ]
}

@test ".sops.yaml may name only active recipients" {
  sed -i.bak "s/${AGE_ACTIVE_CI}/${AGE_UNKNOWN}/" .sops.yaml
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *".sops.yaml rule for ci names a recipient that is not active"* ]] || false
}

@test "a missing allowlist fails closed" {
  rm .sops-recipients.allowlist
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"is missing"* ]] || false
}

@test "lefthook runs the recipient check on every commit" {
  run grep -E 'bash scripts/check-sops-recipients\.sh' "${REPO_ROOT}/lefthook.yml"
  [ "$status" -eq 0 ]
}
