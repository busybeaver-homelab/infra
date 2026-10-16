#!/usr/bin/env bash
# Managed by Ansible - docker_compose_service role. Do not edit manually.
# Encrypts the secret read from stdin into the systemd credential store, but only
# when it differs from the credential already stored there. Prints "changed" or
# "unchanged" so Ansible can report idempotent results. Never prints the secret.
#
# Usage: homelab-compose-credential-sync.sh <name> <credstore_dir> [host|tpm2|host+tpm2|auto]
set -Eeuo pipefail

name="${1:?credential name required}"
credstore_dir="${2:?credential store directory required}"
with_key="${3:-host}"

if [[ ! "${name}" =~ ^[a-z0-9_]+$ ]]; then
  echo "invalid credential name: must match ^[a-z0-9_]+\$" >&2
  exit 2
fi

umask 077
new_value="$(cat)"
if [ -z "${new_value}" ]; then
  echo "refusing to store an empty credential: ${name}" >&2
  exit 2
fi

target="${credstore_dir}/${name}"

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
mv -f "${tmp_file}" "${target}"
trap - EXIT

echo "changed"
