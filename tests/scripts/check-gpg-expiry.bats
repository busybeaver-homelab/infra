#!/usr/bin/env bats
# Tests for scripts/check-gpg-expiry.sh (R2-OPS-04)

load 'helpers/test_helper'

SCRIPT="${REPO_ROOT}/scripts/check-gpg-expiry.sh"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

generate_test_pubkey() {
  local primary_expire="$1"
  local subkey_expire="$2"
  local out_file="$3"
  local gnupghome
  gnupghome="$(mktemp -d /tmp/gnupg.XXXXXX)"
  chmod 700 "${gnupghome}"

  GNUPGHOME="${gnupghome}" gpg --batch --no-tty --pinentry-mode loopback --passphrase '' --generate-key <<EOF >/dev/null 2>&1
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: sign
Subkey-Type: ecdh
Subkey-Curve: cv25519
Subkey-Usage: encrypt
Name-Real: Test Key
Name-Email: test@example.com
Expire-Date: ${primary_expire}
%no-protection
%commit
EOF

  if [ "${subkey_expire}" != "${primary_expire}" ]; then
    local fpr sub_fpr
    fpr="$(GNUPGHOME="${gnupghome}" gpg --batch --no-tty --list-keys --with-colons | awk -F: '$1 == "fpr" { print $10; exit }')"
    sub_fpr="$(GNUPGHOME="${gnupghome}" gpg --batch --no-tty --list-keys --with-colons | awk -F: '$1 == "fpr" { n++; if (n == 2) { print $10; exit } }')"
    GNUPGHOME="${gnupghome}" gpg --batch --no-tty --quick-set-expire "${fpr}" "${subkey_expire}" "${sub_fpr}" >/dev/null 2>&1
  fi

  GNUPGHOME="${gnupghome}" gpg --batch --no-tty --armor --export test@example.com > "${out_file}" 2>/dev/null
  GNUPGHOME="${gnupghome}" gpgconf --kill gpg-agent >/dev/null 2>&1 || true
  rm -rf "${gnupghome}"
}

@test "check-gpg-expiry.sh exits 1 when primary or subkey has no expiry (R2-OPS-04)" {
  local pub="${BATS_TEST_TMPDIR}/no-expiry.pub"
  generate_test_pubkey "0" "0" "${pub}"

  run bash "${SCRIPT}" "${pub}" --warn-days 60
  [ "$status" -eq 1 ]
  [[ "$output" == *"no expiry"* ]] || false
}

@test "check-gpg-expiry.sh exits 1 when encryption subkey has no expiry even if primary expires in 1y (R2-OPS-04)" {
  local pub="${BATS_TEST_TMPDIR}/sub-no-expiry.pub"
  generate_test_pubkey "1y" "0" "${pub}"

  run bash "${SCRIPT}" "${pub}" --warn-days 60
  [ "$status" -eq 1 ]
  [[ "$output" == *"no expiry"* ]] || false
}

@test "check-gpg-expiry.sh exits 1 when key is already expired (R2-OPS-04)" {
  local pub="${BATS_TEST_TMPDIR}/expired.pub"
  generate_test_pubkey "10d" "10d" "${pub}"

  local future_now=$(( $(date +%s) + 20 * 86400 ))
  run env GPG_EXPIRY_NOW_EPOCH="${future_now}" bash "${SCRIPT}" "${pub}" --warn-days 60
  [ "$status" -eq 1 ]
  [[ "$output" == *"expired"* ]] || false
}

@test "check-gpg-expiry.sh exits 2 when key expires within --warn-days window (R2-OPS-04)" {
  local pub="${BATS_TEST_TMPDIR}/expiring-soon.pub"
  generate_test_pubkey "10d" "10d" "${pub}"

  run bash "${SCRIPT}" "${pub}" --warn-days 60
  [ "$status" -eq 2 ]
  [[ "$output" == *"expires within"* ]] || false
}

@test "check-gpg-expiry.sh exits 0 when primary and encryption subkey expire in 1 year (R2-OPS-04)" {
  local pub="${BATS_TEST_TMPDIR}/valid-1y.pub"
  generate_test_pubkey "1y" "1y" "${pub}"

  run bash "${SCRIPT}" "${pub}" --warn-days 60
  [ "$status" -eq 0 ]
}

@test "secrets/gpg-production.pub passes check-gpg-expiry.sh with --warn-days 60 (R2-OPS-04)" {
  run bash "${SCRIPT}" "${REPO_ROOT}/secrets/gpg-production.pub" --warn-days 60
  [ "$status" -eq 0 ]
}

@test "ci.yml runs check-gpg-expiry.sh against secrets/gpg-production.pub (R2-OPS-04)" {
  run grep -F "scripts/check-gpg-expiry.sh secrets/gpg-production.pub" "${REPO_ROOT}/.github/workflows/ci.yml"
  [ "$status" -eq 0 ]
}
