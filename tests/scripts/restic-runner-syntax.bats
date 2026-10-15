#!/usr/bin/env bats
# Tests for configuration/roles/restic_backup/templates/restic-backup-runner.sh.j2
# Static checks on the template plus behavioural tests that render it with Jinja2
# and execute it against stub `restic` / notify binaries.

load 'helpers/test_helper'

RUNNER_TEMPLATE="${REPO_ROOT}/configuration/roles/restic_backup/templates/restic-backup-runner.sh.j2"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

# Renders the runner template into $BATS_TMPDIR/runner.sh with test paths.
render_runner() {
  local auto_init="${1:-false}"
  python3 -c 'import jinja2' 2>/dev/null || skip "python3 with jinja2 is required (run via mise exec)"
  mkdir -p "${BATS_TMPDIR}/etc" "${BATS_TMPDIR}/data" "${BATS_TMPDIR}/libexec" \
    "${BATS_TMPDIR}/bin" "${BATS_TMPDIR}/creds"
  echo "payload" > "${BATS_TMPDIR}/data/file.txt"
  printf 'RESTIC_REPOSITORY=%s/repo\n' "${BATS_TMPDIR}" > "${BATS_TMPDIR}/etc/primary.env"
  : > "${BATS_TMPDIR}/etc/excludes.txt"
  printf 'test-password' > "${BATS_TMPDIR}/creds/restic_password"

  python3 - "${RUNNER_TEMPLATE}" "${BATS_TMPDIR}" "${auto_init}" <<'PY'
import sys
import jinja2

template_path, tmp, auto_init_arg = sys.argv[1], sys.argv[2], sys.argv[3]
auto_init = auto_init_arg.lower() == "true"
with open(template_path, encoding="utf-8") as handle:
    template = jinja2.Template(handle.read(), keep_trailing_newline=True)
rendered = template.render(
    restic_backup_config_dir=f"{tmp}/etc",
    restic_backup_paths=[f"{tmp}/data"],
    restic_backup_secondary_enabled=False,
    restic_backup_libexec_dir=f"{tmp}/libexec",
    restic_backup_auto_init=auto_init,
)
with open(f"{tmp}/runner.sh", "w", encoding="utf-8") as handle:
    handle.write(rendered)
PY
  chmod +x "${BATS_TMPDIR}/runner.sh"

  # Stub restic: logs the subcommand, fails with exit 3 on $STUB_FAIL_ON or $STUB_CAT_RC on cat.
  cat > "${BATS_TMPDIR}/bin/restic" <<'SH'
#!/usr/bin/env bash
sub="$3"
echo "${sub}" >> "${STUB_LOG}"
if [ "${sub}" = "cat" ] && [ -n "${STUB_CAT_RC:-}" ]; then exit "${STUB_CAT_RC}"; fi
if [ "${sub}" = "${STUB_FAIL_ON:-}" ]; then exit 3; fi
exit 0
SH
  # Stub notify helper: records the event.
  cat > "${BATS_TMPDIR}/libexec/restic-backup-notify" <<'SH'
#!/usr/bin/env bash
echo "$1" >> "${NOTIFY_LOG}"
SH
  chmod +x "${BATS_TMPDIR}/bin/restic" "${BATS_TMPDIR}/libexec/restic-backup-notify"
}

run_runner() {
  run env -u RESTIC_PASSWORD_FILE -u RESTIC_REPOSITORY -u AWS_SECRET_ACCESS_KEY \
    PATH="${BATS_TMPDIR}/bin:${PATH}" \
    CREDENTIALS_DIRECTORY="${BATS_TMPDIR}/creds" \
    STUB_LOG="${BATS_TMPDIR}/restic.log" \
    NOTIFY_LOG="${BATS_TMPDIR}/notify.log" \
    STUB_FAIL_ON="${1:-}" \
    STUB_CAT_RC="${STUB_CAT_RC:-}" \
    bash "${BATS_TMPDIR}/runner.sh"
}

@test "rendered runner passes bash syntax check and shellcheck" {
  render_runner
  run bash -n "${BATS_TMPDIR}/runner.sh"
  [ "$status" -eq 0 ]
  if command -v shellcheck >/dev/null 2>&1; then
    run shellcheck -s bash "${BATS_TMPDIR}/runner.sh"
    [ "$status" -eq 0 ]
  fi
}

@test "runner succeeds and sends a success heartbeat when all restic steps succeed" {
  render_runner
  run_runner
  [ "$status" -eq 0 ]
  run cat "${BATS_TMPDIR}/notify.log"
  [ "$output" = "success" ]
  run cat "${BATS_TMPDIR}/restic.log"
  [[ "$output" == *backup* ]] || false
  [[ "$output" == *check* ]]
}

@test "runner fails and sends no heartbeat when restic backup fails but check would pass" {
  render_runner
  run_runner backup
  [ "$status" -eq 1 ]
  [ ! -f "${BATS_TMPDIR}/notify.log" ]
  # The integrity check must not run after a failed backup.
  run grep -x check "${BATS_TMPDIR}/restic.log"
  [ "$status" -eq 1 ]
}

@test "runner fails when restic check fails" {
  render_runner
  run_runner check
  [ "$status" -eq 1 ]
  [ ! -f "${BATS_TMPDIR}/notify.log" ]
}

@test "runner fails when the repository password credential is missing" {
  render_runner
  rm -f "${BATS_TMPDIR}/creds/restic_password"
  run_runner
  [ "$status" -eq 1 ]
  [[ "$output" == *"credential restic_password not available"* ]]
}

@test "runner reads secrets only from the systemd credentials directory" {
  run grep -F 'CREDENTIALS_DIRECTORY' "${RUNNER_TEMPLATE}"
  [ "$status" -eq 0 ]
  run grep -E '/run/secrets|restic_backup_secrets_dir|HEALTHCHECKS_PING_URL' "${RUNNER_TEMPLATE}"
  [ "$status" -eq 1 ]
}

@test "restic runner isolates targets by loading environment files inside subshells" {
  run grep -F 'load_env_file "${env_file}"' "${RUNNER_TEMPLATE}"
  [ "$status" -eq 0 ]
}

@test "restic init is not called when restic cat config fails with generic error (exit 1)" {
  render_runner true
  STUB_CAT_RC=1 run_runner
  [ "$status" -eq 1 ]
  run grep -x init "${BATS_TMPDIR}/restic.log"
  [ "$status" -eq 1 ]
}

@test "restic init is not called when restic cat config fails with exit 10 and restic_backup_auto_init=false" {
  render_runner false
  STUB_CAT_RC=10 run_runner
  [ "$status" -eq 1 ]
  run grep -x init "${BATS_TMPDIR}/restic.log"
  [ "$status" -eq 1 ]
}

@test "restic init is called when restic cat config fails with exit 10 and restic_backup_auto_init=true" {
  render_runner true
  STUB_CAT_RC=10 run_runner
  [ "$status" -eq 0 ]
  run grep -x init "${BATS_TMPDIR}/restic.log"
  [ "$status" -eq 0 ]
}

@test "load_env_file loads KEY=VALUE without executing command substitutions" {
  render_runner
  printf 'RESTIC_REPOSITORY=%s/repo\nSAFE_VAR="$(touch %s/pwned)"\n' "${BATS_TMPDIR}" "${BATS_TMPDIR}" > "${BATS_TMPDIR}/etc/primary.env"
  run_runner
  [ "$status" -eq 0 ]
  [ ! -e "${BATS_TMPDIR}/pwned" ]
}

@test "restic runner executes backup with retry-lock and target labels" {
  run grep -F "restic --retry-lock 2h backup" "${RUNNER_TEMPLATE}"
  [ "$status" -eq 0 ]
  run grep -E '\-\-tag[[:space:]]+"\$\{label\}"' "${RUNNER_TEMPLATE}"
  [ "$status" -eq 0 ]
}

@test "restic runner traps EXIT to guarantee post-backup hooks execution" {
  run grep -F "trap run_post_hooks EXIT" "${RUNNER_TEMPLATE}"
  [ "$status" -eq 0 ]
}

@test "restic runner does not perform forget prune on the host" {
  run grep -E "restic[[:space:]]+forget" "${RUNNER_TEMPLATE}"
  [ "$status" -eq 1 ]
}
