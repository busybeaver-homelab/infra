#!/usr/bin/env bash
set -euo pipefail
DUMP_DIR="/var/backups/containers"
mkdir -p "${DUMP_DIR}"
chmod 0700 "${DUMP_DIR}"

if command -v sqlite3 >/dev/null 2>&1; then
  while IFS= read -r -d '' db; do
    rel="${db#/}"
    safe_name="${rel//\//_}"
    sqlite3 "${db}" ".backup '${DUMP_DIR}/${safe_name}.bak'" || true
  done < <(find /opt/containers /var/lib/docker/volumes -maxdepth 4 \( -name '*.sqlite' -o -name '*.sqlite3' -o -name '*.db' \) -type f -print0 2>/dev/null || true)
fi

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  for cid in $(docker ps --filter "label=homelab.backup.postgres=true" -q); do
    cname="$(docker inspect --format '{{.Name}}' "${cid}" | sed 's#^/##')"
    docker exec "${cid}" pg_dumpall -U postgres >"${DUMP_DIR}/pg-${cname}.sql"
  done
fi
