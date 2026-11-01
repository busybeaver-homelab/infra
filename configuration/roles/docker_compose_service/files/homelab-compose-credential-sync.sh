#!/usr/bin/env bash
# Managed by Ansible - docker_compose_service role. Do not edit manually.
# Encrypts the secret read from stdin into the systemd credential store, but only
# when it differs from the credential already stored there. Prints "changed" or
# "unchanged" so Ansible can report idempotent results. Never prints the secret.
#
# Usage: homelab-compose-credential-sync.sh <name> <credstore_dir> [host|tpm2|host+tpm2|auto] [<dest_file>] [<backup_file>]
#   <dest_file>   bare file name inside <credstore_dir> to write (default: <name>);
#                 the credential is always encrypted under --name=<name>.
#   <backup_file> bare file name inside <credstore_dir>; when set and <dest_file> exists,
#                 the existing file is copied there (mode 0400) just before it is replaced.
set -Eeuo pipefail

name="${1:?credential name required}"
credstore_dir="${2:?credential store directory required}"
with_key="${3:-host}"
dest_file="${4:-${name}}"
backup_file="${5:-}"

if [[ ! "${name}" =~ ^[a-z0-9_]+$ ]]; then
  echo "invalid credential name: must match ^[a-z0-9_]+\$" >&2
  exit 2
fi
if [[ ! "${dest_file}" =~ ^[a-z0-9_.]+$ ]]; then
  echo "invalid destination file name: must match ^[a-z0-9_.]+\$" >&2
  exit 2
fi
if [ -n "${backup_file}" ] && [[ ! "${backup_file}" =~ ^[a-z0-9_.]+$ ]]; then
  echo "invalid backup file name: must match ^[a-z0-9_.]+\$" >&2
  exit 2
fi

umask 077
new_value="$(cat)"
if [ -z "${new_value}" ]; then
  echo "refusing to store an empty credential: ${name}" >&2
  exit 2
fi

target="${credstore_dir}/${dest_file}"

if [ -f "${target}" ]; then
  if current_value="$(systemd-creds decrypt "${target}" - 2>/dev/null)" && [ "${current_value}" = "${new_value}" ]; then
    echo "unchanged"
    exit 0
  fi
fi

tmp_file="$(mktemp "${credstore_dir}/.${name}.XXXXXX")"
trap 'rm -f "${tmp_file}"' EXIT

printf '%s' "${new_value}" | systemd-creds encrypt --with-key="${with_key}" --name="${name}" - "${tmp_file}"
chmod 0400 "${tmp_file}"
if [ -n "${backup_file}" ] && [ -f "${target}" ]; then
  backup_tmp="$(mktemp "${credstore_dir}/.${backup_file}.XXXXXX")"
  trap 'rm -f "${tmp_file}" "${backup_tmp}"' EXIT
  cp "${target}" "${backup_tmp}"
  chmod 0400 "${backup_tmp}"
  mv -f "${backup_tmp}" "${credstore_dir}/${backup_file}"
fi
mv -f "${tmp_file}" "${target}"
trap - EXIT

echo "changed"
