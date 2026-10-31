#!/usr/bin/env bash
# Controller-side byte transport to the robot (BusyBox: no Python, no SFTP).
#
# Usage:
#   robot-transport.sh probe
#   robot-transport.sh push <local_src> <remote_dest>
#   robot-transport.sh pull-calibration <local_dest>
#
# Configuration comes only from the environment:
#   ROBOT_TRANSPORT=ssh|docker
#   ROBOT_HOST, ROBOT_SSH_KEY, ROBOT_KNOWN_HOSTS   (ssh)
#   ROBOT_CONTAINER                                (docker, Molecule only)
#
# Exit codes: 2 usage/configuration, 7 host key changed, 8 robot unreachable;
# otherwise the status of the failed transfer. The SSH key is only passed as a
# path and its contents are never read or printed.

set -euo pipefail

TMP_FILES=()

cleanup() {
  if ((${#TMP_FILES[@]} > 0)); then
    rm -f -- "${TMP_FILES[@]}"
  fi
}
trap cleanup EXIT

die() {
  local code="$1"
  shift
  printf 'ERROR: %s\n' "$*" >&2
  exit "${code}"
}

usage() {
  printf 'usage: %s probe | push <local_src> <remote_dest> | pull-calibration <local_dest>\n' \
    "${0##*/}" >&2
  exit 2
}

require_env() {
  local name
  for name in "$@"; do
    [[ -n "${!name:-}" ]] || die 2 "${name} is not set"
  done
}

# Quotes one word for a POSIX shell (BusyBox ash on the robot).
sh_quote() {
  local q="'\\''"
  printf "'%s'" "${1//\'/${q}}"
}

check_config() {
  case "${ROBOT_TRANSPORT:-}" in
    ssh) require_env ROBOT_HOST ROBOT_SSH_KEY ROBOT_KNOWN_HOSTS ;;
    docker) require_env ROBOT_CONTAINER ;;
    *) die 2 "ROBOT_TRANSPORT must be 'ssh' or 'docker'" ;;
  esac
}

# Runs one shell command on the robot; stdin/stdout/stderr are passed through.
remote() {
  local cmd="$1"
  case "${ROBOT_TRANSPORT}" in
    ssh)
      ssh -i "${ROBOT_SSH_KEY}" \
        -o UserKnownHostsFile="${ROBOT_KNOWN_HOSTS}" \
        -o StrictHostKeyChecking=accept-new \
        -o BatchMode=yes \
        root@"${ROBOT_HOST}" "${cmd}"
      ;;
    docker)
      docker exec -i "${ROBOT_CONTAINER}" sh -c "${cmd}"
      ;;
  esac
}

cmd_probe() {
  local err_file
  err_file="$(mktemp)"
  TMP_FILES+=("${err_file}")
  # Raw transport errors are captured, not shown: callers get one clear line.
  if remote true </dev/null >/dev/null 2>"${err_file}"; then
    return 0
  fi
  if grep -Eq 'REMOTE HOST IDENTIFICATION HAS CHANGED|Host key verification failed' "${err_file}"; then
    die 7 "robot host key changed (factory reset?). Remove its entry from ${ROBOT_KNOWN_HOSTS:-the robot known-hosts file} (runbook: \"Clearing a host key\"), then re-run."
  fi
  if [[ "${ROBOT_TRANSPORT}" == docker ]]; then
    die 8 "robot container not reachable: ${ROBOT_CONTAINER}"
  fi
  die 8 "robot not reachable over SSH at ${ROBOT_HOST}"
}

cmd_push() {
  (($# == 2)) || usage
  local src="$1" dest="$2" qdest qpart
  [[ -n "${dest}" ]] || usage
  [[ -f "${src}" && -r "${src}" ]] || die 2 "local source not readable: ${src}"
  qdest="$(sh_quote "${dest}")"
  qpart="$(sh_quote "${dest}.part")"
  remote "cat > ${qpart} && mv ${qpart} ${qdest} || { rm -f ${qpart}; exit 1; }" <"${src}"
}

cmd_pull_calibration() {
  (($# == 1)) || usage
  local dest="$1" part
  [[ -n "${dest}" ]] || usage
  part="${dest}.part"
  TMP_FILES+=("${part}")
  # shellcheck disable=SC2016 # expanded by the robot's shell, not here
  remote 'set -- /mnt/private /mnt/misc; for f in /etc/OTA_Key_pub.pem /etc/publickey.pem; do [ -e "$f" ] && set -- "$@" "$f"; done; tar cf - "$@"' \
    </dev/null >"${part}"
  [[ -s "${part}" ]] || die 1 "calibration archive from the robot is empty"
  mv -f -- "${part}" "${dest}"
}

main() {
  (($# >= 1)) || usage
  local sub="$1"
  shift
  case "${sub}" in
    probe | push | pull-calibration) ;;
    *) usage ;;
  esac
  check_config
  case "${sub}" in
    probe)
      (($# == 0)) || usage
      cmd_probe
      ;;
    push) cmd_push "$@" ;;
    pull-calibration) cmd_pull_calibration "$@" ;;
  esac
}

main "$@"
