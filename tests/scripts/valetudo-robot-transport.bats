#!/usr/bin/env bats
# Tests for configuration/roles/valetudo_robot/files/robot-transport.sh
# (controller-side byte transport to the robot: ssh in production, docker exec
# in Molecule). ssh/docker/scp/sftp are stubbed on PATH; fixtures use only
# RFC 5737 addresses and throwaway files (no real key material).

load 'helpers/test_helper'

SCRIPT="${REPO_ROOT}/configuration/roles/valetudo_robot/files/robot-transport.sh"
TEST_HOST='192.0.2.10'

setup() {
  setup_tmpdir
  STUB_BIN="${BATS_TMPDIR}/bin"
  STUB_LOG="${BATS_TMPDIR}/stub.log"
  STUB_STDIN="${BATS_TMPDIR}/stub.stdin"
  mkdir -p "${STUB_BIN}"
  : >"${STUB_LOG}"
  export STUB_LOG STUB_STDIN

  # ssh stub: logs argv (one per line), captures stdin, serves canned
  # stdout/stderr and exit status.
  cat >"${STUB_BIN}/ssh" <<'SSH'
#!/usr/bin/env bash
printf 'ssh\n' >>"${STUB_LOG}"
printf 'ARG:%s\n' "$@" >>"${STUB_LOG}"
cat >"${STUB_STDIN}"
if [[ -n "${STUB_SSH_STDOUT_FILE:-}" ]]; then
  cat "${STUB_SSH_STDOUT_FILE}"
fi
if [[ -n "${STUB_SSH_STDERR:-}" ]]; then
  printf '%s\n' "${STUB_SSH_STDERR}" >&2
fi
exit "${STUB_SSH_EXIT:-0}"
SSH

  # docker stub: logs argv, then really runs `sh -c <cmd>` locally so the
  # remote command and its quoting are exercised end to end.
  cat >"${STUB_BIN}/docker" <<'DOCKER'
#!/usr/bin/env bash
printf 'docker\n' >>"${STUB_LOG}"
printf 'ARG:%s\n' "$@" >>"${STUB_LOG}"
[[ "$1" == exec && "$2" == -i && "$4" == sh && "$5" == -c ]] || exit 99
if [[ -n "${STUB_DOCKER_TRUNCATE:-}" ]]; then
  # Simulates a link that drops mid-transfer: the remote side sees early EOF.
  head -c "${STUB_DOCKER_TRUNCATE}" | sh -c "$6"
  exit $?
fi
exec sh -c "$6"
DOCKER

  # scp/sftp must never be used (the robot has no SFTP subsystem).
  for forbidden in scp sftp; do
    cat >"${STUB_BIN}/${forbidden}" <<FORBIDDEN
#!/usr/bin/env bash
printf 'FORBIDDEN ${forbidden}\n' >>"\${STUB_LOG}"
exit 97
FORBIDDEN
  done
  chmod 0755 "${STUB_BIN}"/*

  # Dummy key file: content is irrelevant to the stubs and is never real.
  ROBOT_SSH_KEY="${BATS_TMPDIR}/id_test"
  : >"${ROBOT_SSH_KEY}"
  ROBOT_KNOWN_HOSTS="${BATS_TMPDIR}/known_hosts_robot"
  ROBOT_HOST="${TEST_HOST}"
  ROBOT_TRANSPORT='ssh'
  export ROBOT_SSH_KEY ROBOT_KNOWN_HOSTS ROBOT_HOST ROBOT_TRANSPORT
  unset ROBOT_CONTAINER STUB_SSH_STDOUT_FILE STUB_SSH_STDERR STUB_SSH_EXIT

  prepend_path "${STUB_BIN}"
}

teardown() {
  teardown_tmpdir
}

# Prints the logged argv of the first stubbed call, one argument per line.
logged_args() {
  sed -n 's/^ARG://p' "${STUB_LOG}"
}

@test "ssh probe builds the exact ssh options and runs true" {
  run "${SCRIPT}" probe
  [ "${status}" -eq 0 ]
  expected="$(printf '%s\n' \
    -i "${ROBOT_SSH_KEY}" \
    -o "UserKnownHostsFile=${ROBOT_KNOWN_HOSTS}" \
    -o StrictHostKeyChecking=accept-new \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=3 \
    "root@${TEST_HOST}" \
    true)"
  [ "$(logged_args)" = "${expected}" ]
  run ! grep -q FORBIDDEN "${STUB_LOG}"
}

@test "push over ssh streams stdin into a .part file then renames it" {
  printf 'payload-bytes\n' >"${BATS_TMPDIR}/src"
  run "${SCRIPT}" push "${BATS_TMPDIR}/src" /data/.incoming/valetudo
  [ "${status}" -eq 0 ]
  remote_cmd="$(logged_args | tail -n 1)"
  # payload-bytes plus newline is 14 bytes; the size is verified before mv.
  [[ "${remote_cmd}" == *"cat > '/data/.incoming/valetudo.part' && [ \"\$(wc -c < '/data/.incoming/valetudo.part')\" -eq 14 ] && mv '/data/.incoming/valetudo.part' '/data/.incoming/valetudo'"* ]] || false
  [ "$(cat "${STUB_STDIN}")" = 'payload-bytes' ]
  logged_args | grep -qx -- 'BatchMode=yes'
  run ! grep -Eq 'FORBIDDEN|scp|sftp' "${STUB_LOG}"
}

@test "push over docker writes the destination atomically via docker exec" {
  export ROBOT_TRANSPORT='docker' ROBOT_CONTAINER='robot-sim'
  unset ROBOT_HOST ROBOT_SSH_KEY ROBOT_KNOWN_HOSTS
  dest_dir="${BATS_TMPDIR}/remote dir"
  mkdir -p "${dest_dir}"
  printf 'docker-payload\n' >"${BATS_TMPDIR}/src"
  run "${SCRIPT}" push "${BATS_TMPDIR}/src" "${dest_dir}/it's.bin"
  [ "${status}" -eq 0 ]
  [ "$(cat "${dest_dir}/it's.bin")" = 'docker-payload' ]
  [ ! -e "${dest_dir}/it's.bin.part" ]
  [ "$(logged_args | head -n 5 | tr '\n' ' ')" = 'exec -i robot-sim sh -c ' ]
  run ! grep -Eq '^ssh$|FORBIDDEN' "${STUB_LOG}"
}

@test "push never promotes a truncated transfer" {
  export ROBOT_TRANSPORT='docker' ROBOT_CONTAINER='robot-sim' STUB_DOCKER_TRUNCATE=5
  dest_dir="${BATS_TMPDIR}/remote"
  mkdir -p "${dest_dir}"
  printf 'twenty-bytes-payload' >"${BATS_TMPDIR}/src"
  run "${SCRIPT}" push "${BATS_TMPDIR}/src" "${dest_dir}/postboot.block"
  [ "${status}" -ne 0 ]
  [ ! -e "${dest_dir}/postboot.block" ]
  [ ! -e "${dest_dir}/postboot.block.part" ]
}

@test "push hides raw transport stderr" {
  export STUB_SSH_STDERR='ssh: connect to host 192.0.2.10 port 22: Connection refused' STUB_SSH_EXIT=255
  printf 'x' >"${BATS_TMPDIR}/src"
  run "${SCRIPT}" push "${BATS_TMPDIR}/src" /data/.incoming/valetudo
  [ "${status}" -ne 0 ]
  [[ "${output}" != *"Connection refused"* ]] || false
  [[ "${output}" != *"192.0.2.10"* ]] || false
  [[ "${output}" == *"ERROR: push to robot failed"* ]] || false
}

@test "push fails when the local source is missing" {
  run "${SCRIPT}" push "${BATS_TMPDIR}/missing" /data/.incoming/valetudo
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"local source not readable"* ]] || false
  [ ! -s "${STUB_LOG}" ]
}

@test "unknown ROBOT_TRANSPORT gives exit 2" {
  export ROBOT_TRANSPORT='telnet'
  run "${SCRIPT}" probe
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"ROBOT_TRANSPORT"* ]] || false
  [ ! -s "${STUB_LOG}" ]
}

@test "unset ROBOT_TRANSPORT gives exit 2" {
  unset ROBOT_TRANSPORT
  run "${SCRIPT}" probe
  [ "${status}" -eq 2 ]
  [ ! -s "${STUB_LOG}" ]
}

@test "ssh mode fails closed when a required variable is missing" {
  unset ROBOT_KNOWN_HOSTS
  run "${SCRIPT}" probe
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"ROBOT_KNOWN_HOSTS"* ]] || false
  [ ! -s "${STUB_LOG}" ]
}

@test "unknown subcommand gives exit 2" {
  run "${SCRIPT}" frobnicate
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"usage"* ]] || false
}

@test "pull-calibration streams the calibration tar and leaves no .part file" {
  printf 'canned-tar-bytes' >"${BATS_TMPDIR}/canned.tar"
  export STUB_SSH_STDOUT_FILE="${BATS_TMPDIR}/canned.tar"
  dest="${BATS_TMPDIR}/out/x40-ultra-20261031T000000Z.tar"
  mkdir -p "${BATS_TMPDIR}/out"
  run "${SCRIPT}" pull-calibration "${dest}"
  [ "${status}" -eq 0 ]
  [ "$(cat "${dest}")" = 'canned-tar-bytes' ]
  [ ! -e "${dest}.part" ]
  remote_cmd="$(logged_args | tail -n 1)"
  [[ "${remote_cmd}" == *"tar cf - "* ]] || false
  [[ "${remote_cmd}" == *"/mnt/private /mnt/misc"* ]] || false
  [[ "${remote_cmd}" == *"/etc/OTA_Key_pub.pem"* ]] || false
  [[ "${remote_cmd}" == *"/etc/publickey.pem"* ]] || false
  run ! grep -q FORBIDDEN "${STUB_LOG}"
}

@test "pull-calibration failure leaves neither the destination nor a .part file" {
  printf 'partial' >"${BATS_TMPDIR}/canned.tar"
  export STUB_SSH_STDOUT_FILE="${BATS_TMPDIR}/canned.tar" STUB_SSH_EXIT=1
  dest="${BATS_TMPDIR}/x40-ultra.tar"
  run "${SCRIPT}" pull-calibration "${dest}"
  [ "${status}" -ne 0 ]
  [ ! -e "${dest}" ]
  [ ! -e "${dest}.part" ]
}

@test "pull-calibration hides raw transport stderr" {
  export STUB_SSH_STDERR='ssh: connect to host 192.0.2.10 port 22: Connection refused' STUB_SSH_EXIT=255
  dest="${BATS_TMPDIR}/x40-ultra.tar"
  run "${SCRIPT}" pull-calibration "${dest}"
  [ "${status}" -ne 0 ]
  [[ "${output}" != *"Connection refused"* ]] || false
  [[ "${output}" != *"192.0.2.10"* ]] || false
  [[ "${output}" == *"ERROR: calibration pull from robot failed"* ]] || false
  [ ! -e "${dest}" ]
  [ ! -e "${dest}.part" ]
}

@test "pull-calibration refuses to overwrite an existing destination" {
  printf 'canned-tar-bytes' >"${BATS_TMPDIR}/canned.tar"
  export STUB_SSH_STDOUT_FILE="${BATS_TMPDIR}/canned.tar"
  dest="${BATS_TMPDIR}/x40-ultra.tar"
  printf 'earlier-backup' >"${dest}"
  run "${SCRIPT}" pull-calibration "${dest}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"already exists"* ]] || false
  [ "$(cat "${dest}")" = 'earlier-backup' ]
  [ ! -s "${STUB_LOG}" ]
}

@test "pull-calibration refuses an empty archive" {
  : >"${BATS_TMPDIR}/canned.tar"
  export STUB_SSH_STDOUT_FILE="${BATS_TMPDIR}/canned.tar"
  dest="${BATS_TMPDIR}/x40-ultra.tar"
  run "${SCRIPT}" pull-calibration "${dest}"
  [ "${status}" -ne 0 ]
  [ ! -e "${dest}" ]
  [ ! -e "${dest}.part" ]
}

@test "preflight explains host key mismatch" {
  export STUB_SSH_STDERR='Host key verification failed.' STUB_SSH_EXIT=255
  run --separate-stderr "${SCRIPT}" probe
  [ "${status}" -eq 7 ]
  [ "${stderr}" = "ERROR: robot host key changed (factory reset?). Remove its entry from ${ROBOT_KNOWN_HOSTS} (runbook: \"Clearing a host key\"), then re-run." ]
}

@test "probe maps REMOTE HOST IDENTIFICATION HAS CHANGED to exit 7" {
  export STUB_SSH_STDERR='@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @' STUB_SSH_EXIT=255
  run "${SCRIPT}" probe
  [ "${status}" -eq 7 ]
  [[ "${output}" == *"${ROBOT_KNOWN_HOSTS}"* ]] || false
  [[ "${output}" != *"WARNING"* ]] || false
}

@test "probe with a generic ssh failure gives exit 8 without a raw ssh trace" {
  export STUB_SSH_STDERR='ssh: connect to host 192.0.2.10 port 22: Operation timed out' STUB_SSH_EXIT=255
  run --separate-stderr "${SCRIPT}" probe
  [ "${status}" -eq 8 ]
  [ "${stderr}" = "ERROR: robot not reachable over SSH at ${TEST_HOST}" ]
  [ -z "${output}" ]
}

@test "probe never prints the ssh key path contents" {
  printf 'SYNTHETIC-KEY-MATERIAL-%s\n' "$(openssl rand -hex 8)" >"${ROBOT_SSH_KEY}"
  export STUB_SSH_STDERR='generic failure' STUB_SSH_EXIT=255
  run "${SCRIPT}" probe
  [ "${status}" -eq 8 ]
  [[ "${output}" != *"SYNTHETIC-KEY-MATERIAL"* ]] || false
}
