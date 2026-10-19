#!/usr/bin/env bats
# Unit tests for state snapshot integration in scripts/drift.sh and wrappers (R2-TF-07 / REV2-P2-8).

load 'helpers/test_helper'

setup() {
  setup_tmpdir
  STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  EVENT_LOG="${BATS_TEST_TMPDIR}/events.log"
  mkdir -p "${STUB_BIN}" "${BATS_TEST_TMPDIR}/module"
  : >"${EVENT_LOG}"

  export SOPS_FILE="${BATS_TEST_TMPDIR}/nonexistent.sops.yaml"
  export SNAPSHOT_STATE_SCRIPT="${STUB_BIN}/snapshot-state-stub.sh"
  export EVENT_LOG

  cat >"${SNAPSHOT_STATE_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
echo "SNAPSHOT: $*" >> "${EVENT_LOG}"
exit "${STUB_SNAPSHOT_RC:-0}"
EOF

  cat >"${STUB_BIN}/tofu" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *" init "*)
    echo "TOFU_INIT" >> "${EVENT_LOG}"
    exit 0
    ;;
  *" plan "*)
    echo "TOFU_PLAN" >> "${EVENT_LOG}"
    exit 0
    ;;
esac
EOF

  chmod +x "${SNAPSHOT_STATE_SCRIPT}" "${STUB_BIN}/tofu"
  export PATH="${STUB_BIN}:${PATH}"
}

teardown() {
  teardown_tmpdir
}

@test "scripts/drift.sh --all calls snapshot-state.sh --all before any tofu plan" {
  DRIFT_MODULES="cloudflare dns" run "${REPO_ROOT}/scripts/drift.sh" --all --no-init
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "${EVENT_LOG}")" = "SNAPSHOT: --all" ]
  grep -q "^TOFU_PLAN$" "${EVENT_LOG}"
}

@test "drift-cloudflare.sh and drift-dns.sh wrappers pass --module <m> to snapshot-state.sh" {
  run "${REPO_ROOT}/scripts/drift-cloudflare.sh" --module-dir "${BATS_TEST_TMPDIR}/module" --no-init
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "${EVENT_LOG}")" = "SNAPSHOT: --module cloudflare" ]
  grep -q "^TOFU_PLAN$" "${EVENT_LOG}"

  : >"${EVENT_LOG}"
  run "${REPO_ROOT}/scripts/drift-dns.sh" --module-dir "${BATS_TEST_TMPDIR}/module" --no-init
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "${EVENT_LOG}")" = "SNAPSHOT: --module dns" ]
  grep -q "^TOFU_PLAN$" "${EVENT_LOG}"
}

@test "DRIFT_SKIP_STATE_SNAPSHOT=true opts out of state snapshots" {
  DRIFT_SKIP_STATE_SNAPSHOT=true \
    run "${REPO_ROOT}/scripts/drift.sh" --module cloudflare --module-dir "${BATS_TEST_TMPDIR}/module" --no-init
  [ "$status" -eq 0 ]
  ! grep -q "^SNAPSHOT:" "${EVENT_LOG}"
  grep -q "^TOFU_PLAN$" "${EVENT_LOG}"
}

@test "scripts/drift.sh exits 1 before planning when state snapshot fails" {
  STUB_SNAPSHOT_RC=1 \
    run "${REPO_ROOT}/scripts/drift.sh" --module cloudflare --module-dir "${BATS_TEST_TMPDIR}/module" --no-init
  [ "$status" -eq 1 ]
  [ "$(head -n 1 "${EVENT_LOG}")" = "SNAPSHOT: --module cloudflare" ]
  ! grep -q "^TOFU_PLAN$" "${EVENT_LOG}"
}

@test "mise state:snapshot task defaults to --all" {
  run yq eval -p=toml -o=yaml '.tasks["state:snapshot"].run' "${REPO_ROOT}/mise.toml"
  [ "$status" -eq 0 ]
  [ "$output" = "bash scripts/snapshot-state.sh --all" ]
}

@test "scripts/drift.sh logs a stderr warning if the Healthchecks.io ping fails (R2-CI-06)" {
  cat >"${STUB_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
exit 22
EOF
  chmod +x "${STUB_BIN}/curl"
  HEALTHCHECKS_DRIFT_PING_URL="https://hc-ping.example.test/00000000-0000-0000-0000-000000000099" \
    DRIFT_MODULES="cloudflare" \
    run "${REPO_ROOT}/scripts/drift.sh" --all --no-init
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: Healthchecks.io drift heartbeat ping failed"* ]] || false
}
