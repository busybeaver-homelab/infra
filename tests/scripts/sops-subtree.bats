#!/usr/bin/env bats
# Tests for scripts/sops-subtree.sh (R2-TF-02 / REV2-P1-3).

load 'helpers/test_helper'

SCRIPT="${REPO_ROOT}/scripts/sops-subtree.sh"

setup() {
  TMP_DIR="${BATS_TEST_TMPDIR}/sops-subtree"
  mkdir -p "${TMP_DIR}/bin"
}

@test "sops-subtree extracts requested subtree as compact JSON string" {
  cat > "${TMP_DIR}/bin/sops" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-d" && "$2" == "--extract" && "$3" == '["cloudflare"]["config"]' ]]; then
  printf 'account_name: example\nzones:\n  primary:\n    name: example.com\n'
  exit 0
fi
exit 1
EOF
  chmod +x "${TMP_DIR}/bin/sops"
  touch "${TMP_DIR}/secrets.sops.yaml"

  run env PATH="${TMP_DIR}/bin:${PATH}" bash -c \
    "printf '{\"file\":\"%s\",\"extract\":\"[\\\\\"cloudflare\\\\\"][\\\\\"config\\\\\"]\"}' '${TMP_DIR}/secrets.sops.yaml' | bash '${SCRIPT}'"
  [ "$status" -eq 0 ]
  parsed="$(printf '%s' "$output" | jq -r '.json | fromjson | .zones.primary.name')"
  [ "$parsed" = "example.com" ]
}

@test "sops-subtree fails closed when sops fails" {
  cat > "${TMP_DIR}/bin/sops" <<'EOF'
#!/usr/bin/env bash
echo "sops decryption failed" >&2
exit 1
EOF
  chmod +x "${TMP_DIR}/bin/sops"
  touch "${TMP_DIR}/secrets.sops.yaml"

  run env PATH="${TMP_DIR}/bin:${PATH}" bash -c \
    "printf '{\"file\":\"%s\",\"extract\":\"[\\\\\"cloudflare\\\\\"]\"}' '${TMP_DIR}/secrets.sops.yaml' | bash '${SCRIPT}'"
  [ "$status" -ne 0 ]
}

@test "sops-subtree fails closed on missing file or query keys" {
  run bash -c "printf '{}' | bash '${SCRIPT}'"
  [ "$status" -ne 0 ]

  run bash -c "printf '{\"file\":\"/nonexistent.yaml\",\"extract\":\"[\\\\\"a\\\\\"]\"}' | bash '${SCRIPT}'"
  [ "$status" -ne 0 ]
}
