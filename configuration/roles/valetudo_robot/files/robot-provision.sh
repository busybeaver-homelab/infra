#!/bin/sh
# Robot-side provisioning for a rooted Dreame X40 Ultra (BusyBox userland).
# Piped over SSH by Ansible: sh -s -- [--root DIR] <command> [args]
#
# Commands (paths are relative to --root, default /):
#   check-space <required_kib>
#   install <staged_rel> <dest_rel> <sha256>
#   postboot <staged_block_rel>
#   backup-status
#   mark-backup <sha256>
#   tailscale-join <hostname> <tag> <authkey_rel>
#
# Mutating commands print exactly one stdout line: CHANGED=0 or CHANGED=1.
# Errors go to stderr. Exit codes: 2 usage, 3 no space, 4 checksum mismatch,
# 5 postboot template missing, 6 tailscale up failed, 7 malformed markers.
# Secrets are never echoed: the Tailscale auth key is only handled as a path.

set -eu

BEGIN_MARK='# BEGIN homelab-managed (valetudo_robot)'
END_MARK='# END homelab-managed (valetudo_robot)'
TS_SOCKET='/tmp/tailscaled.sock'

ROOT='/'
TMP_FILE=''
KEY_FILE=''

cleanup() {
  if [ -n "${TMP_FILE}" ]; then
    rm -f -- "${TMP_FILE}"
  fi
  if [ -n "${KEY_FILE}" ]; then
    rm -f -- "${KEY_FILE}"
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

die() {
  _code=$1
  shift
  printf 'ERROR: %s\n' "$*" >&2
  exit "${_code}"
}

# resolve <rel>: print the path under ROOT; reject traversal and empty input.
resolve() {
  case "$1" in
    '') die 2 'empty path argument' ;;
    .. | ../* | */.. | */../*) die 2 'path traversal is not allowed' ;;
  esac
  printf '%s/%s' "${ROOT}" "${1#/}"
}

is_sha256() {
  case "$1" in
    *[!0-9a-fA-F]*) return 1 ;;
  esac
  [ "${#1}" -eq 64 ]
}

lower() {
  printf '%s' "$1" | tr 'A-F' 'a-f'
}

# file_sha <file>: print the lowercase sha256; abort (exit 2) unless the tool
# produced a valid 64-hex digest, so an empty result is never compared as a hash.
# Call it as a plain assignment (_x=$(file_sha f)) so set -e propagates the abort.
file_sha() {
  _fs=$(sha256sum "$1" 2>/dev/null | {
    read -r _sum _rest || :
    printf '%s' "${_sum:-}"
  }) || :
  is_sha256 "${_fs}" || die 2 'could not compute a sha256 checksum'
  printf '%s' "${_fs}" | tr 'A-F' 'a-f'
}

emit_changed() {
  printf 'CHANGED=%s\n' "$1"
}

# ensure_dir <dir>: create the directory when absent.
ensure_dir() {
  mkdir -p -- "$1"
}

cmd_check_space() {
  [ $# -eq 1 ] || die 2 'usage: check-space <required_kib>'
  case "$1" in
    '' | *[!0-9]*) die 2 'required_kib must be a non-negative integer' ;;
  esac
  _required=$1
  ensure_dir "${ROOT}/data"
  # Join wrapped lines (long device names) and take the Available column.
  _line=$(df -k "${ROOT}/data" | sed '1d' | tr '\n' ' ')
  # shellcheck disable=SC2086
  set -- ${_line}
  _have=${4:-}
  case "${_have}" in
    '' | *[!0-9]*) die 2 'unable to determine free space on /data' ;;
  esac
  if [ "${_have}" -lt "${_required}" ]; then
    die 3 "insufficient space on /data: need ${_required} KiB, have ${_have} KiB"
  fi
}

cmd_install() {
  [ $# -eq 3 ] || die 2 'usage: install <staged_rel> <dest_rel> <sha256>'
  _staged=$(resolve "$1")
  _dest=$(resolve "$2")
  is_sha256 "$3" || die 2 'sha256 must be 64 hexadecimal characters'
  _want=$(lower "$3")
  [ -f "${_staged}" ] || die 2 'staged file not found'

  _have=$(file_sha "${_staged}")
  if [ "${_have}" != "${_want}" ]; then
    rm -f -- "${_staged}"
    die 4 'staged file checksum mismatch'
  fi

  _current=''
  if [ -f "${_dest}" ]; then
    _current=$(file_sha "${_dest}")
  fi
  if [ "${_current}" = "${_want}" ]; then
    rm -f -- "${_staged}"
    emit_changed 0
    return 0
  fi

  chmod 0755 "${_staged}"
  ensure_dir "$(dirname -- "${_dest}")"
  sync
  mv -f -- "${_staged}" "${_dest}"
  emit_changed 1
}

# emit_block <file>: print the file, guaranteeing a trailing newline.
emit_block() {
  cat -- "$1"
  if [ -s "$1" ] && [ -n "$(tail -c 1 -- "$1")" ]; then
    printf '\n'
  fi
}

cmd_postboot() {
  [ $# -eq 1 ] || die 2 'usage: postboot <staged_block_rel>'
  _block=$(resolve "$1")
  [ -f "${_block}" ] || die 2 'staged block not found'
  _target="${ROOT}/data/_root_postboot.sh"
  _tpl="${ROOT}/misc/_root_postboot.sh.tpl"

  _created=0
  _src=${_target}
  if [ ! -f "${_target}" ]; then
    [ -f "${_tpl}" ] || die 5 'postboot template /misc/_root_postboot.sh.tpl is missing and /data/_root_postboot.sh does not exist'
    _src=${_tpl}
    _created=1
  fi

  ensure_dir "${ROOT}/data"
  TMP_FILE=$(mktemp "${ROOT}/data/.postboot.XXXXXX")

  _begin_n=$(grep -c -x -F -- "${BEGIN_MARK}" "${_src}" || true)
  _end_n=$(grep -c -x -F -- "${END_MARK}" "${_src}" || true)

  if [ "${_begin_n}" -eq 0 ] && [ "${_end_n}" -eq 0 ]; then
    {
      cat -- "${_src}"
      if [ -s "${_src}" ] && [ -n "$(tail -c 1 -- "${_src}")" ]; then
        printf '\n'
      fi
      printf '%s\n' "${BEGIN_MARK}"
      emit_block "${_block}"
      printf '%s\n' "${END_MARK}"
    } >"${TMP_FILE}"
  elif [ "${_begin_n}" -eq 1 ] && [ "${_end_n}" -eq 1 ]; then
    _begin_ln=$(grep -n -x -F -- "${BEGIN_MARK}" "${_src}")
    _begin_ln=${_begin_ln%%:*}
    _end_ln=$(grep -n -x -F -- "${END_MARK}" "${_src}")
    _end_ln=${_end_ln%%:*}
    [ "${_begin_ln}" -lt "${_end_ln}" ] || die 7 'postboot markers are out of order'
    {
      sed -n "1,${_begin_ln}p" "${_src}"
      emit_block "${_block}"
      sed -n "${_end_ln},\$p" "${_src}"
    } >"${TMP_FILE}"
  else
    die 7 'postboot managed-block markers are malformed (expected exactly one BEGIN and one END)'
  fi

  if [ "${_created}" -eq 0 ]; then
    _new_sha=$(file_sha "${TMP_FILE}")
    _cur_sha=$(file_sha "${_target}")
    if [ "${_new_sha}" = "${_cur_sha}" ]; then
      emit_changed 0
      return 0
    fi
  fi

  chmod 0755 "${TMP_FILE}"
  sync
  mv -f -- "${TMP_FILE}" "${_target}"
  TMP_FILE=''
  emit_changed 1
}

cmd_backup_status() {
  [ $# -eq 0 ] || die 2 'usage: backup-status'
  _marker="${ROOT}/data/.calibration-backup"
  _value=''
  if [ -f "${_marker}" ]; then
    read -r _value <"${_marker}" || true
  fi
  if [ -n "${_value}" ]; then
    printf '%s\n' "${_value}"
  else
    printf 'NONE\n'
  fi
}

cmd_mark_backup() {
  [ $# -eq 1 ] || die 2 'usage: mark-backup <sha256>'
  is_sha256 "$1" || die 2 'sha256 must be 64 hexadecimal characters'
  _want=$(lower "$1")
  _marker="${ROOT}/data/.calibration-backup"
  _value=''
  if [ -f "${_marker}" ]; then
    read -r _value <"${_marker}" || true
  fi
  if [ "${_value}" = "${_want}" ]; then
    emit_changed 0
    return 0
  fi
  ensure_dir "${ROOT}/data"
  printf '%s\n' "${_want}" >"${_marker}"
  emit_changed 1
}

cmd_tailscale_join() {
  [ $# -eq 3 ] || die 2 'usage: tailscale-join <hostname> <tag> <authkey_rel>'
  _host=$1
  _tag=$2
  # Set before any validation so the key file is removed on every exit path.
  case "$3" in
    '' | .. | ../* | */.. | */../*) die 2 'invalid authkey path' ;;
  esac
  KEY_FILE=$(resolve "$3")

  case "${_host}" in
    '' | -* | *[!A-Za-z0-9-]*) die 2 'invalid hostname' ;;
  esac
  case "${_tag}" in
    tag: | tag:*[!A-Za-z0-9-]*) die 2 'invalid tag (expected tag:<name>)' ;;
    tag:*) ;;
    *) die 2 'invalid tag (expected tag:<name>)' ;;
  esac

  _ts="${ROOT}/data/tailscale/tailscale"
  [ -x "${_ts}" ] || die 2 'tailscale CLI not found under /data/tailscale'

  _status=$("${_ts}" --socket="${TS_SOCKET}" status --json 2>/dev/null || true)
  if printf '%s\n' "${_status}" | grep -q '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
    emit_changed 0
    return 0
  fi

  [ -f "${KEY_FILE}" ] || die 2 'auth key file not found'
  if ! "${_ts}" --socket="${TS_SOCKET}" up \
    --auth-key="file:${KEY_FILE}" \
    --hostname="${_host}" \
    --advertise-tags="${_tag}" >&2; then
    die 6 'tailscale up failed'
  fi
  emit_changed 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || die 2 '--root requires a directory'
      ROOT=$2
      shift 2
      ;;
    --root=*)
      ROOT=${1#--root=}
      shift
      ;;
    *) break ;;
  esac
done
ROOT=${ROOT%/}

[ $# -ge 1 ] || die 2 'usage: robot-provision.sh [--root DIR] <command> [args]'
_cmd=$1
shift

case "${_cmd}" in
  check-space) cmd_check_space "$@" ;;
  install) cmd_install "$@" ;;
  postboot) cmd_postboot "$@" ;;
  backup-status) cmd_backup_status "$@" ;;
  mark-backup) cmd_mark_backup "$@" ;;
  tailscale-join) cmd_tailscale_join "$@" ;;
  *) die 2 "unknown command: ${_cmd}" ;;
esac
