#!/usr/bin/env bats
# Tests for configuration/roles/valetudo_robot/files/robot-provision.sh
# (robot-side POSIX sh provisioning script; all paths resolved under --root).

load 'helpers/test_helper'

SCRIPT="${REPO_ROOT}/configuration/roles/valetudo_robot/files/robot-provision.sh"
BEGIN_MARK='# BEGIN homelab-managed (valetudo_robot)'
END_MARK='# END homelab-managed (valetudo_robot)'

setup() {
  setup_tmpdir
  ROOT="${BATS_TMPDIR}/root"
  STUB_BIN="${BATS_TMPDIR}/bin"
  STUB_LOG="${BATS_TMPDIR}/stub.log"
  mkdir -p "${ROOT}/data/.incoming" "${ROOT}/data/tailscale" "${ROOT}/misc" "${STUB_BIN}"
  : >"${STUB_LOG}"
  export STUB_LOG

  # BusyBox provides sha256sum on the robot; macOS hosts only ship shasum.
  if ! command -v sha256sum >/dev/null 2>&1; then
    cat >"${STUB_BIN}/sha256sum" <<'SHIM'
#!/bin/sh
exec shasum -a 256 "$@"
SHIM
    chmod 0755 "${STUB_BIN}/sha256sum"
  fi

  # df stub: POSIX `df -k` layout with a configurable Available column.
  cat >"${STUB_BIN}/df" <<'DF'
#!/bin/sh
printf 'df %s\n' "$*" >>"${STUB_LOG}"
printf 'Filesystem 1K-blocks Used Available Use%% Mounted on\n'
printf '/dev/stub 1000000 1000 %s 1%% /data\n' "${STUB_DF_AVAIL:-500000}"
DF
  chmod 0755 "${STUB_BIN}/df"

  # tailscale stub placed where the script expects the real CLI.
  cat >"${ROOT}/data/tailscale/tailscale" <<'TS'
#!/bin/sh
printf 'tailscale %s\n' "$*" >>"${STUB_LOG}"
case "$*" in
  *" status --json"*)
    printf '{\n  "Version": "stub",\n  "BackendState": "%s"\n}\n' "${STUB_TS_STATE:-Stopped}"
    ;;
  *" up "*)
    [ "${STUB_TS_UP_FAIL:-0}" = "1" ] && exit 1
    exit 0
    ;;
esac
TS
  chmod 0755 "${ROOT}/data/tailscale/tailscale"

  prepend_path "${STUB_BIN}"
}

teardown() {
  teardown_tmpdir
}

provision() {
  "${PROVISION_SH:-sh}" "${SCRIPT}" --root "${ROOT}" "$@"
}

sha_of() {
  sha256sum "$1" | cut -d' ' -f1
}

file_mode() {
  ls -l "$1" | cut -c2-10
}

# ---------------------------------------------------------------- check-space

@test "check-space passes when enough space is available" {
  STUB_DF_AVAIL=2048 run provision check-space 1024
  [ "$status" -eq 0 ]
  grep -Fq "df -k ${ROOT}/data" "${STUB_LOG}"
}

@test "check-space passes when available equals required" {
  STUB_DF_AVAIL=1024 run provision check-space 1024
  [ "$status" -eq 0 ]
}

@test "check-space fails with exit 3 and the exact message" {
  STUB_DF_AVAIL=512 run --separate-stderr provision check-space 1024
  [ "$status" -eq 3 ]
  [ "$stderr" = "ERROR: insufficient space on /data: need 1024 KiB, have 512 KiB" ]
  [ -z "$output" ]
}

@test "check-space rejects a non-numeric requirement" {
  run --separate-stderr provision check-space lots
  [ "$status" -eq 2 ]
}

# -------------------------------------------------------------------- install

stage_file() {
  # stage_file <name> <content> -> prints sha256
  printf '%s' "$2" >"${ROOT}/data/.incoming/$1"
  sha_of "${ROOT}/data/.incoming/$1"
}

@test "install fresh binary reports CHANGED=1 with mode 0755" {
  sum="$(stage_file valetudo 'binary-v1')"
  run provision install /data/.incoming/valetudo /data/valetudo "$sum"
  [ "$status" -eq 0 ]
  [ "$output" = "CHANGED=1" ]
  [ "$(cat "${ROOT}/data/valetudo")" = "binary-v1" ]
  [ "$(file_mode "${ROOT}/data/valetudo")" = "rwxr-xr-x" ]
  [ ! -e "${ROOT}/data/.incoming/valetudo" ]
}

@test "install creates a missing destination directory" {
  sum="$(stage_file tailscaled 'daemon-v1')"
  run provision install /data/.incoming/tailscaled /data/newdir/tailscaled "$sum"
  [ "$status" -eq 0 ]
  [ "$output" = "CHANGED=1" ]
  [ -x "${ROOT}/data/newdir/tailscaled" ]
}

@test "install of an identical artifact reports CHANGED=0 and removes the staged file" {
  sum="$(stage_file valetudo 'binary-v1')"
  run provision install /data/.incoming/valetudo /data/valetudo "$sum"
  [ "$output" = "CHANGED=1" ]

  sum="$(stage_file valetudo 'binary-v1')"
  run provision install /data/.incoming/valetudo /data/valetudo "$sum"
  [ "$status" -eq 0 ]
  [ "$output" = "CHANGED=0" ]
  [ ! -e "${ROOT}/data/.incoming/valetudo" ]
  [ "$(cat "${ROOT}/data/valetudo")" = "binary-v1" ]
}

@test "install of a changed artifact reports CHANGED=1 and replaces dest" {
  sum="$(stage_file valetudo 'binary-v1')"
  run provision install /data/.incoming/valetudo /data/valetudo "$sum"
  [ "$output" = "CHANGED=1" ]

  sum="$(stage_file valetudo 'binary-v2')"
  run provision install /data/.incoming/valetudo /data/valetudo "$sum"
  [ "$status" -eq 0 ]
  [ "$output" = "CHANGED=1" ]
  [ "$(cat "${ROOT}/data/valetudo")" = "binary-v2" ]
}

@test "install with a bad checksum exits 4, removes staged file, keeps dest" {
  sum="$(stage_file valetudo 'binary-v1')"
  run provision install /data/.incoming/valetudo /data/valetudo "$sum"
  [ "$output" = "CHANGED=1" ]

  stage_file valetudo 'tampered' >/dev/null
  bad="$(printf '%064d' 0)"
  run --separate-stderr provision install /data/.incoming/valetudo /data/valetudo "$bad"
  [ "$status" -eq 4 ]
  [ -z "$output" ]
  [[ "$stderr" == "ERROR:"* ]] || false
  [ ! -e "${ROOT}/data/.incoming/valetudo" ]
  [ "$(cat "${ROOT}/data/valetudo")" = "binary-v1" ]
}

@test "install rejects path traversal in relative paths" {
  sum="$(stage_file valetudo 'binary-v1')"
  run --separate-stderr provision install /data/.incoming/valetudo /data/../escape "$sum"
  [ "$status" -eq 2 ]
  [ ! -e "${ROOT}/escape" ]
}

@test "install rejects a malformed checksum argument" {
  stage_file valetudo 'binary-v1' >/dev/null
  run --separate-stderr provision install /data/.incoming/valetudo /data/valetudo not-a-sha
  [ "$status" -eq 2 ]
  [ ! -e "${ROOT}/data/valetudo" ]
}

# -------------------------------------------------------------------- postboot

write_template() {
  printf '#!/bin/sh\n# stock template\nexport TEMPLATE=1\n' >"${ROOT}/misc/_root_postboot.sh.tpl"
}

write_block() {
  printf '%s\n' "$@" >"${ROOT}/data/.incoming/postboot.block"
}

@test "postboot creates the file from the template with the managed block" {
  write_template
  write_block 'echo one' 'echo two'
  run provision postboot /data/.incoming/postboot.block
  [ "$status" -eq 0 ]
  [ "$output" = "CHANGED=1" ]
  expected="$(printf '#!/bin/sh\n# stock template\nexport TEMPLATE=1\n%s\necho one\necho two\n%s\n' "${BEGIN_MARK}" "${END_MARK}")"
  [ "$(cat "${ROOT}/data/_root_postboot.sh")" = "${expected}" ]
  [ "$(file_mode "${ROOT}/data/_root_postboot.sh")" = "rwxr-xr-x" ]
}

@test "postboot second run is idempotent" {
  write_template
  write_block 'echo one'
  run provision postboot /data/.incoming/postboot.block
  [ "$output" = "CHANGED=1" ]
  before="$(sha_of "${ROOT}/data/_root_postboot.sh")"
  run provision postboot /data/.incoming/postboot.block
  [ "$status" -eq 0 ]
  [ "$output" = "CHANGED=0" ]
  [ "$(sha_of "${ROOT}/data/_root_postboot.sh")" = "${before}" ]
}

@test "postboot preserves lines outside the markers byte-for-byte" {
  printf '#!/bin/sh\n\tkeep  trailing  \nbefore\\n\n%s\nold\n%s\nafter $VAR "q"\n\n  last\n' \
    "${BEGIN_MARK}" "${END_MARK}" >"${ROOT}/data/_root_postboot.sh"
  chmod 0755 "${ROOT}/data/_root_postboot.sh"
  write_block 'echo new'
  run provision postboot /data/.incoming/postboot.block
  [ "$status" -eq 0 ]
  [ "$output" = "CHANGED=1" ]
  printf '#!/bin/sh\n\tkeep  trailing  \nbefore\\n\n%s\necho new\n%s\nafter $VAR "q"\n\n  last\n' \
    "${BEGIN_MARK}" "${END_MARK}" >"${BATS_TMPDIR}/expected"
  cmp "${BATS_TMPDIR}/expected" "${ROOT}/data/_root_postboot.sh"
}

@test "postboot replaces only the inner content when the block changes" {
  write_template
  write_block 'echo one'
  run provision postboot /data/.incoming/postboot.block
  [ "$output" = "CHANGED=1" ]
  write_block 'echo changed' 'echo more'
  run provision postboot /data/.incoming/postboot.block
  [ "$status" -eq 0 ]
  [ "$output" = "CHANGED=1" ]
  expected="$(printf '#!/bin/sh\n# stock template\nexport TEMPLATE=1\n%s\necho changed\necho more\n%s\n' "${BEGIN_MARK}" "${END_MARK}")"
  [ "$(cat "${ROOT}/data/_root_postboot.sh")" = "${expected}" ]
}

@test "postboot appends markers to an existing file without markers" {
  printf '#!/bin/sh\nuser line' >"${ROOT}/data/_root_postboot.sh"
  write_block 'echo one'
  run provision postboot /data/.incoming/postboot.block
  [ "$status" -eq 0 ]
  [ "$output" = "CHANGED=1" ]
  expected="$(printf '#!/bin/sh\nuser line\n%s\necho one\n%s\n' "${BEGIN_MARK}" "${END_MARK}")"
  [ "$(cat "${ROOT}/data/_root_postboot.sh")" = "${expected}" ]
}

@test "postboot without template and without postboot file exits 5" {
  write_block 'echo one'
  run --separate-stderr provision postboot /data/.incoming/postboot.block
  [ "$status" -eq 5 ]
  [ -z "$output" ]
  [ ! -e "${ROOT}/data/_root_postboot.sh" ]
}

@test "postboot with a missing template succeeds when the file already exists" {
  printf '#!/bin/sh\n' >"${ROOT}/data/_root_postboot.sh"
  write_block 'echo one'
  run provision postboot /data/.incoming/postboot.block
  [ "$status" -eq 0 ]
  [ "$output" = "CHANGED=1" ]
}

@test "postboot refuses malformed markers and leaves the file untouched" {
  printf '#!/bin/sh\n%s\nunterminated\n' "${BEGIN_MARK}" >"${ROOT}/data/_root_postboot.sh"
  before="$(sha_of "${ROOT}/data/_root_postboot.sh")"
  write_block 'echo one'
  run --separate-stderr provision postboot /data/.incoming/postboot.block
  [ "$status" -eq 7 ]
  [ -z "$output" ]
  [ "$(sha_of "${ROOT}/data/_root_postboot.sh")" = "${before}" ]
}

@test "postboot leaves no temporary files behind" {
  write_template
  write_block 'echo one'
  run provision postboot /data/.incoming/postboot.block
  [ "$status" -eq 0 ]
  run ls -A "${ROOT}/data"
  [[ "$output" != *.postboot.* ]] || false
}

# ------------------------------------------------------- backup-status / mark

@test "backup-status prints NONE when unmarked" {
  run provision backup-status
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "mark-backup then backup-status round-trips the checksum" {
  sum="$(printf 'calibration' | sha256sum | cut -d' ' -f1)"
  run provision mark-backup "$sum"
  [ "$status" -eq 0 ]
  [ "$output" = "CHANGED=1" ]
  run provision backup-status
  [ "$status" -eq 0 ]
  [ "$output" = "$sum" ]
  run provision mark-backup "$sum"
  [ "$output" = "CHANGED=0" ]
}

@test "mark-backup rejects a malformed checksum" {
  run --separate-stderr provision mark-backup nope
  [ "$status" -eq 2 ]
  [ ! -e "${ROOT}/data/.calibration-backup" ]
}

# ------------------------------------------------------------ tailscale-join

write_key() {
  printf 'synthetic-key-material' >"${ROOT}/data/.incoming/authkey"
}

@test "tailscale-join is a no-op when BackendState is Running" {
  write_key
  STUB_TS_STATE=Running run provision tailscale-join robot-test tag:type-iot /data/.incoming/authkey
  [ "$status" -eq 0 ]
  [ "$output" = "CHANGED=0" ]
  grep -Fq -- "--socket=/tmp/tailscaled.sock status --json" "${STUB_LOG}"
  run grep -F " up " "${STUB_LOG}"
  [ "$status" -ne 0 ]
  [ ! -e "${ROOT}/data/.incoming/authkey" ]
}

@test "tailscale-join runs tailscale up when not Running" {
  write_key
  STUB_TS_STATE=Stopped run provision tailscale-join robot-test tag:type-iot /data/.incoming/authkey
  [ "$status" -eq 0 ]
  [ "$output" = "CHANGED=1" ]
  grep -Fq -- "--auth-key=file:${ROOT}/data/.incoming/authkey" "${STUB_LOG}"
  grep -Fq -- "--hostname=robot-test" "${STUB_LOG}"
  grep -Fq -- "--advertise-tags=tag:type-iot" "${STUB_LOG}"
  grep -Fq -- "--socket=/tmp/tailscaled.sock up" "${STUB_LOG}"
  [ ! -e "${ROOT}/data/.incoming/authkey" ]
  run grep -F "synthetic-key-material" "${STUB_LOG}"
  [ "$status" -ne 0 ]
}

@test "tailscale-join removes the key file and exits 6 when tailscale up fails" {
  write_key
  STUB_TS_STATE=Stopped STUB_TS_UP_FAIL=1 run --separate-stderr \
    provision tailscale-join robot-test tag:type-iot /data/.incoming/authkey
  [ "$status" -eq 6 ]
  [ -z "$output" ]
  [ ! -e "${ROOT}/data/.incoming/authkey" ]
  [[ "$stderr" != *synthetic-key-material* ]] || false
}

@test "tailscale-join removes the key file on usage errors" {
  write_key
  run --separate-stderr provision tailscale-join "bad host" tag:type-iot /data/.incoming/authkey
  [ "$status" -eq 2 ]
  [ ! -e "${ROOT}/data/.incoming/authkey" ]
}

@test "tailscale-join rejects an invalid tag and removes the key file" {
  write_key
  run --separate-stderr provision tailscale-join robot-test 'type-iot' /data/.incoming/authkey
  [ "$status" -eq 2 ]
  [ ! -e "${ROOT}/data/.incoming/authkey" ]
  write_key
  run --separate-stderr provision tailscale-join robot-test 'tag:a b' /data/.incoming/authkey
  [ "$status" -eq 2 ]
  [ ! -e "${ROOT}/data/.incoming/authkey" ]
}

# ----------------------------------------------------------------- CLI / misc

@test "unknown command exits 2" {
  run --separate-stderr provision frobnicate
  [ "$status" -eq 2 ]
}

@test "missing command exits 2" {
  run --separate-stderr provision
  [ "$status" -eq 2 ]
}

@test "script is POSIX sh" {
  run mise exec -- shellcheck -s sh "${SCRIPT}"
  [ "$status" -eq 0 ]
  head -n 1 "${SCRIPT}" | grep -Fxq '#!/bin/sh'
  if command -v busybox >/dev/null 2>&1; then
    run busybox sh -n "${SCRIPT}"
    [ "$status" -eq 0 ]
  fi
  if command -v dash >/dev/null 2>&1; then
    run dash -n "${SCRIPT}"
    [ "$status" -eq 0 ]
  fi
}
