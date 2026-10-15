#!/usr/bin/env bats
# Tests for the restic_backup helper scripts:
#   configuration/roles/restic_backup/files/restic-credential-sync.sh
#   configuration/roles/restic_backup/files/restic-backup-notify.sh

load 'helpers/test_helper'

SYNC_SCRIPT="${REPO_ROOT}/configuration/roles/restic_backup/files/restic-credential-sync.sh"
NOTIFY_SCRIPT="${REPO_ROOT}/configuration/roles/restic_backup/files/restic-backup-notify.sh"

setup() {
  setup_tmpdir
  mkdir -p "${BATS_TMPDIR}/bin" "${BATS_TMPDIR}/credstore" "${BATS_TMPDIR}/creds"
  chmod 700 "${BATS_TMPDIR}/credstore"

  # Stub systemd-creds: "encrypts" by prefixing ENC: and records the embedded name.
  cat > "${BATS_TMPDIR}/bin/systemd-creds" <<'SH'
#!/usr/bin/env bash
cmd="$1"; shift
case "${cmd}" in
  encrypt)
    name=""; key=""
    for arg in "$@"; do
      case "${arg}" in
        --name=*) name="${arg#--name=}" ;;
        --with-key=*) key="${arg#--with-key=}" ;;
      esac
    done
    out="${*: -1}"
    { printf 'ENC:%s:%s:' "${name}" "${key}"; cat; } > "${out}"
    ;;
  decrypt)
    content="$(cat "$1")"
    printf '%s' "${content#ENC:*:*:}"
    ;;
  *) exit 1 ;;
esac
SH
  # Stub curl: records argv and the --config stdin.
  cat > "${BATS_TMPDIR}/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CURL_ARGV_LOG}"
cat >> "${CURL_CONFIG_LOG}"
exit "${CURL_EXIT:-0}"
SH
  chmod +x "${BATS_TMPDIR}/bin/systemd-creds" "${BATS_TMPDIR}/bin/curl"
  prepend_path "${BATS_TMPDIR}/bin"
}

teardown() {
  teardown_tmpdir
}

sync_cred() {
  run bash -c "printf '%s' \"\$1\" | bash '${SYNC_SCRIPT}' \"\$2\" '${BATS_TMPDIR}/credstore' host" _ "$1" "$2"
}

@test "credential-sync stores a new credential encrypted with the requested key and mode 0400" {
  sync_cred "s3cr3t-value" restic_password
  [ "$status" -eq 0 ]
  [ "$output" = "changed" ]
  run cat "${BATS_TMPDIR}/credstore/restic_password"
  [ "$output" = "ENC:restic_password:host:s3cr3t-value" ]
  local file="${BATS_TMPDIR}/credstore/restic_password" mode
  mode="$(stat -c '%a' "${file}" 2>/dev/null || stat -f '%Lp' "${file}")"
  [ "${mode}" = "400" ]
}

@test "credential-sync reports unchanged when the stored value is identical" {
  sync_cred "s3cr3t-value" restic_password
  [ "$output" = "changed" ]
  sync_cred "s3cr3t-value" restic_password
  [ "$status" -eq 0 ]
  [ "$output" = "unchanged" ]
}

@test "credential-sync re-encrypts when the value changes" {
  sync_cred "old-value" restic_password
  sync_cred "new-value" restic_password
  [ "$status" -eq 0 ]
  [ "$output" = "changed" ]
  run cat "${BATS_TMPDIR}/credstore/restic_password"
  [ "$output" = "ENC:restic_password:host:new-value" ]
}

@test "credential-sync never prints the secret" {
  sync_cred "do-not-print-me" restic_password
  [[ "$output" != *do-not-print-me* ]]
}

@test "credential-sync rejects invalid credential names" {
  sync_cred "value" "../escape"
  [ "$status" -eq 2 ]
  [ ! -e "${BATS_TMPDIR}/escape" ]
}

@test "credential-sync refuses to store an empty credential" {
  sync_cred "" restic_password
  [ "$status" -eq 2 ]
  [ ! -e "${BATS_TMPDIR}/credstore/restic_password" ]
}

notify() {
  run env CREDENTIALS_DIRECTORY="${BATS_TMPDIR}/creds" \
    CURL_ARGV_LOG="${BATS_TMPDIR}/curl-argv.log" \
    CURL_CONFIG_LOG="${BATS_TMPDIR}/curl-config.log" \
    CURL_EXIT="${CURL_EXIT:-0}" \
    bash "${NOTIFY_SCRIPT}" "$@"
}

@test "notify sends the success heartbeat via curl --config without the URL in argv" {
  printf 'https://hc.example.com/ping/abc' > "${BATS_TMPDIR}/creds/healthchecks_ping_url"
  notify success restic-backup.service
  [ "$status" -eq 0 ]
  run cat "${BATS_TMPDIR}/curl-config.log"
  [ "$output" = 'url = "https://hc.example.com/ping/abc"' ]
  run grep -F 'hc.example.com' "${BATS_TMPDIR}/curl-argv.log"
  [ "$status" -eq 1 ]
}

@test "notify sends the failure signal to the /fail endpoint" {
  printf 'https://hc.example.com/ping/abc' > "${BATS_TMPDIR}/creds/healthchecks_ping_url"
  notify fail restic-backup.service
  [ "$status" -eq 0 ]
  run cat "${BATS_TMPDIR}/curl-config.log"
  [ "$output" = 'url = "https://hc.example.com/ping/abc/fail"' ]
}

@test "notify skips cleanly when no ping URL credential is configured" {
  notify fail restic-backup.service
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping fail signal"* ]] || false
  [ ! -f "${BATS_TMPDIR}/curl-argv.log" ]
}

@test "notify surfaces an undeliverable failure signal but tolerates a missed heartbeat" {
  printf 'https://hc.example.com/ping/abc' > "${BATS_TMPDIR}/creds/healthchecks_ping_url"
  CURL_EXIT=7 notify fail restic-backup.service
  [ "$status" -eq 1 ]
  CURL_EXIT=7 notify success restic-backup.service
  [ "$status" -eq 0 ]
}

@test "notify rejects unknown events" {
  notify bogus
  [ "$status" -eq 2 ]
}
