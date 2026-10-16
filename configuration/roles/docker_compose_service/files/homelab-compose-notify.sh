#!/usr/bin/env bash
# Managed by Ansible - docker_compose_service role. Do not edit manually.
# Sends a Healthchecks.io signal for the Docker Compose GitOps reconciler or cleanup job.
#   homelab-compose-notify.sh success [unit]  -> heartbeat ping
#   homelab-compose-notify.sh fail [unit]     -> /fail ping (called from the OnFailure unit)
# The ping URL is read from the systemd credential "compose_healthchecks_ping_url" and is passed
# to curl via stdin (--config -), so it never appears in process arguments or logs.
set -Eeuo pipefail

event="${1:-success}"
unit="${2:-homelab-compose-reconcile.service}"

case "${event}" in
  success) suffix="" ;;
  fail) suffix="/fail" ;;
  *)
    echo "unknown event: ${event} (expected success|fail)" >&2
    exit 2
    ;;
esac

url_file="${CREDENTIALS_DIRECTORY:-}/compose_healthchecks_ping_url"
if [ -z "${CREDENTIALS_DIRECTORY:-}" ] || [ ! -s "${url_file}" ]; then
  echo "No Healthchecks ping URL configured; skipping ${event} signal" >&2
  exit 0
fi

ping_url="$(cat "${url_file}")"

# Sentinel from the failure unit's SetCredential= fallback: the encrypted credential exists in the
# unit but could not be loaded from the credential store.
if [ "${ping_url}" = "missing" ]; then
  echo "Healthchecks ping URL credential could not be loaded from the credential store; ${event} signal not sent" >&2
  [ "${event}" = "fail" ] && exit 1
  exit 0
fi

if printf 'url = "%s%s"\n' "${ping_url}" "${suffix}" |
  curl -fsS -m 10 --retry 3 -o /dev/null --data-raw "${event}: ${unit} on $(hostname)" --config -; then
  echo "Healthchecks ${event} signal sent"
  exit 0
fi

echo "Warning: Healthchecks ${event} signal could not be delivered" >&2
# A missed success heartbeat is caught by the dead-man's switch; a missed failure
# signal must surface as a failed unit in the journal.
[ "${event}" = "fail" ] && exit 1
exit 0
