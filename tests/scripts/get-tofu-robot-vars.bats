#!/usr/bin/env bats
# Unit tests for scripts/get-tofu-robot-vars.sh using stubbed tofu/sops/jq binaries and a
# synthetic, runtime-generated mesh output fixture. Never runs against live OpenTofu state.

bats_require_minimum_version 1.5.0

load 'helpers/test_helper'

SCRIPT="${REPO_ROOT}/scripts/get-tofu-robot-vars.sh"

setup() {
  FIXTURE_DIR="${BATS_TEST_TMPDIR}/fixtures"
  STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  FAKE_INFRA="${BATS_TEST_TMPDIR}/infrastructure"
  mkdir -p "${FIXTURE_DIR}" "${STUB_BIN}" "${FAKE_INFRA}/mesh"

  ROBOT_KEY="tskey-auth-test-$(openssl rand -hex 8)"

  printf '{\n  "robot_auth_key": { "sensitive": true, "type": "string", "value": "%s" },\n  "webhook_endpoint_url": { "sensitive": true, "type": "string", "value": "https://hooks.example.test/x" }\n}\n' \
    "${ROBOT_KEY}" >"${FIXTURE_DIR}/mesh.json"

  # tofu stub: logs argv and the backend env it saw, then serves the mesh fixture.
  cat >"${STUB_BIN}/tofu" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'tofu %s\n' "$*" >>"$BATS_TEST_TMPDIR/argv.log"
printf 'ak=%s region=%s endpoint=%s pass=%s\n' "${AWS_ACCESS_KEY_ID:-}" "${AWS_DEFAULT_REGION:-}" \
  "${AWS_ENDPOINT_URL_S3:-}" "${TF_VAR_state_encryption_passphrase:-}" >>"$BATS_TEST_TMPDIR/tofu.calls"
cat "$FIXTURE_DIR/mesh.json"
STUB
  chmod +x "${STUB_BIN}/tofu"

  cat >"${STUB_BIN}/sops" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'sops %s\n' "$*" >>"$BATS_TEST_TMPDIR/argv.log"
echo "x" >>"$BATS_TEST_TMPDIR/sops.calls"
extract=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--extract" ]]; then
    extract="$arg"
  fi
  prev="$arg"
done
case "$extract" in
  *'["opentofu"]["cloudflare_r2_access_key_id"]'*) echo "backend-ak-synthetic" ;;
  *'["opentofu"]["cloudflare_r2_secret_access_key"]'*) echo "backend-sk-synthetic" ;;
  *'["opentofu"]["state_encryption_passphrase"]'*) echo "backend-passphrase-synthetic-0000000000" ;;
  *'["cloudflare"]["account_id"]'*) echo "00000000000000000000000000000000" ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "${STUB_BIN}/sops"

  # jq wrapper: logs argv, then delegates to the real jq.
  REAL_JQ="$(command -v jq)"
  cat >"${STUB_BIN}/jq" <<'STUB'
#!/usr/bin/env bash
printf 'jq %s\n' "$*" >>"$BATS_TEST_TMPDIR/argv.log"
exec "$REAL_JQ" "$@"
STUB
  chmod +x "${STUB_BIN}/jq"

  export FIXTURE_DIR REAL_JQ
  export SOPS_FILE="${BATS_TEST_TMPDIR}/fake.sops.yaml"
  : >"${SOPS_FILE}"
  prepend_path "${STUB_BIN}"
}

@test "emits tofu_robot_auth_key from mesh json" {
  run --separate-stderr "${SCRIPT}" --mesh-json "${FIXTURE_DIR}/mesh.json"
  [ "$status" -eq 0 ]
  [ "$("${REAL_JQ}" -r '.tofu_robot_auth_key' <<<"${output}")" = "${ROBOT_KEY}" ]
  [ "$("${REAL_JQ}" -r 'keys | join(",")' <<<"${output}")" = "tofu_robot_auth_key" ]
  [ "$("${REAL_JQ}" -s 'length' <<<"${output}")" = "1" ]

  # Fixture mode never touches SOPS or tofu.
  [ ! -f "${BATS_TEST_TMPDIR}/sops.calls" ]
  [ ! -f "${BATS_TEST_TMPDIR}/tofu.calls" ]
}

@test "fails closed with empty stdout when robot_auth_key missing" {
  "${REAL_JQ}" 'del(.robot_auth_key)' "${FIXTURE_DIR}/mesh.json" >"${FIXTURE_DIR}/missing.json"

  run --separate-stderr "${SCRIPT}" --mesh-json "${FIXTURE_DIR}/missing.json"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"ERROR: Missing required OpenTofu output robot_auth_key in module mesh"* ]] || false
}

@test "fails closed with empty stdout when robot_auth_key empty" {
  "${REAL_JQ}" '.robot_auth_key.value = ""' "${FIXTURE_DIR}/mesh.json" >"${FIXTURE_DIR}/empty.json"

  run --separate-stderr "${SCRIPT}" --mesh-json "${FIXTURE_DIR}/empty.json"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"ERROR: Invalid OpenTofu output robot_auth_key in module mesh (expected non-empty string)"* ]] || false
}

@test "fails closed with empty stdout when robot_auth_key is not a string" {
  "${REAL_JQ}" '.robot_auth_key.value = null' "${FIXTURE_DIR}/mesh.json" >"${FIXTURE_DIR}/null.json"

  run --separate-stderr "${SCRIPT}" --mesh-json "${FIXTURE_DIR}/null.json"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"ERROR: Invalid OpenTofu output robot_auth_key in module mesh (expected non-empty string)"* ]] || false
  [[ "$stderr" != *"Missing"* ]] || false
}

@test "fails closed with empty stdout when mesh json is not an object or is missing" {
  printf '[]\n' >"${FIXTURE_DIR}/array.json"
  run --separate-stderr "${SCRIPT}" --mesh-json "${FIXTURE_DIR}/array.json"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"not a JSON object"* ]] || false

  run --separate-stderr "${SCRIPT}" --mesh-json "${FIXTURE_DIR}/does-not-exist.json"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"Output JSON file not found"* ]] || false
}

@test "never passes the key via argv" {
  # Live mode: stubbed tofu serves the fixture, stubbed sops supplies synthetic backend secrets.
  export AWS_ACCESS_KEY_ID="caller-ak-must-not-reach-backend"
  run --separate-stderr "${SCRIPT}" --tofu-dir "${FAKE_INFRA}"
  [ "$status" -eq 0 ]
  [ "$("${REAL_JQ}" -r '.tofu_robot_auth_key' <<<"${output}")" = "${ROBOT_KEY}" ]

  # Fixture mode as well.
  run --separate-stderr "${SCRIPT}" --mesh-json "${FIXTURE_DIR}/mesh.json"
  [ "$status" -eq 0 ]

  [ -s "${BATS_TEST_TMPDIR}/argv.log" ]
  run grep -E '^tofu .*output -json' "${BATS_TEST_TMPDIR}/argv.log"
  [ "$status" -eq 0 ]
  run grep -c '^jq ' "${BATS_TEST_TMPDIR}/argv.log"
  [ "$output" -ge 1 ]
  run grep -F "${ROBOT_KEY}" "${BATS_TEST_TMPDIR}/argv.log"
  [ "$status" -ne 0 ]

  # Live mode reaches tofu with SOPS backend credentials, not the caller's AWS_* keys.
  [ "$(wc -l <"${BATS_TEST_TMPDIR}/tofu.calls" | tr -d ' ')" -eq 1 ]
  run grep -c "ak=backend-ak-synthetic region=auto endpoint=https://00000000000000000000000000000000.r2.cloudflarestorage.com pass=backend-passphrase-synthetic-0000000000" "${BATS_TEST_TMPDIR}/tofu.calls"
  [ "$output" = "1" ]
}

@test "live mode fails closed when SOPS backend secrets cannot be decrypted" {
  printf '#!/usr/bin/env bash\nexit 1\n' >"${STUB_BIN}/sops"
  chmod +x "${STUB_BIN}/sops"

  run --separate-stderr "${SCRIPT}" --tofu-dir "${FAKE_INFRA}"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"Could not decrypt opentofu."* ]] || false
  [ ! -f "${BATS_TEST_TMPDIR}/tofu.calls" ]
}

@test "live mode fails closed when the mesh module cannot be read" {
  cat >"${STUB_BIN}/tofu" <<'STUB'
#!/usr/bin/env bash
echo "Error: Backend initialization required" >&2
exit 1
STUB
  chmod +x "${STUB_BIN}/tofu"

  run --separate-stderr "${SCRIPT}" --tofu-dir "${FAKE_INFRA}"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"Failed to read OpenTofu outputs from infrastructure/mesh"* ]] || false
}

@test "--help exits 0" {
  [ -x "${SCRIPT}" ]
  run "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: scripts/get-tofu-robot-vars.sh"* ]] || false
  [[ "$output" == *"--mesh-json <path>"* ]] || false

  run shellcheck "${SCRIPT}"
  [ "$status" -eq 0 ]
  run shfmt -d -i 2 -ci "${SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "unknown option exits 1" {
  run --separate-stderr "${SCRIPT}" --bogus
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"ERROR: Unknown argument: --bogus"* ]] || false

  run --separate-stderr "${SCRIPT}" --mesh-json
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"--mesh-json requires a value"* ]] || false
}
