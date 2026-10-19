#!/usr/bin/env bash
set -euo pipefail

# Verify that a GPG public key file has finite, non-expired expiration dates on
# both its primary key (pub) and its encryption subkey(s) (sub with e/E usage).
#
# Usage: scripts/check-gpg-expiry.sh <pubkey-file> [--warn-days <days>]
# Exit codes:
#   0 - All checked keys have a finite expiry beyond the warning window
#   1 - Key file missing/invalid, or any checked key has no expiry or is expired
#   2 - Any checked key expires within the --warn-days window (default: 60)

usage() {
  echo "Usage: $0 <pubkey-file> [--warn-days <days>]" >&2
  exit 1
}

if [ "$#" -lt 1 ]; then
  usage
fi

PUBKEY_FILE="$1"
shift

WARN_DAYS=60
while [ "$#" -gt 0 ]; do
  case "$1" in
    --warn-days)
      if [ "$#" -lt 2 ]; then
        usage
      fi
      WARN_DAYS="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if ! [[ "$WARN_DAYS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --warn-days must be a non-negative integer (got '$WARN_DAYS')." >&2
  exit 1
fi

if [ ! -s "$PUBKEY_FILE" ]; then
  echo "ERROR: GPG public key file not found or empty: $PUBKEY_FILE" >&2
  exit 1
fi

TMP_GNUPGHOME="$(mktemp -d /tmp/gnupg-expiry.XXXXXX)"
chmod 700 "$TMP_GNUPGHOME"
trap 'rm -rf "$TMP_GNUPGHOME"' EXIT

NOW_EPOCH="${GPG_EXPIRY_NOW_EPOCH:-$(date +%s)}"
WARN_SECONDS=$((WARN_DAYS * 86400))
WARN_THRESHOLD=$((NOW_EPOCH + WARN_SECONDS))

COLON_OUTPUT="$(GNUPGHOME="$TMP_GNUPGHOME" gpg --batch --no-tty --show-keys --with-colons "$PUBKEY_FILE" 2>/dev/null || true)"

if [ -z "$COLON_OUTPUT" ]; then
  echo "ERROR: Failed to parse GPG public key from $PUBKEY_FILE" >&2
  exit 1
fi

found_pub=0
hard_fail=0
warn_fail=0

while IFS=: read -r rectype validity _ _ keyid created expires _ _ _ _ capabilities _; do
  if [ "$rectype" = "pub" ]; then
    found_pub=1
  elif [ "$rectype" = "sub" ]; then
    # Check encryption-capable subkeys (or subkeys where capabilities are omitted)
    if [ -n "$capabilities" ] && [[ ! "$capabilities" =~ [eE] ]]; then
      continue
    fi
  else
    continue
  fi

  label="${rectype}:${keyid:-unknown}"

  if [ "$validity" = "r" ]; then
    echo "ERROR: GPG key $label in $PUBKEY_FILE is revoked (created=${created:-unknown})." >&2
    hard_fail=1
    continue
  fi

  if [ -z "$expires" ] || ! [[ "$expires" =~ ^[0-9]+$ ]] || [ "$expires" -eq 0 ]; then
    echo "ERROR: GPG key $label in $PUBKEY_FILE has no expiry date set." >&2
    hard_fail=1
    continue
  fi

  if [ "$validity" = "e" ] || [ "$expires" -le "$NOW_EPOCH" ]; then
    echo "ERROR: GPG key $label in $PUBKEY_FILE is expired (expiry_epoch=$expires <= now=$NOW_EPOCH)." >&2
    hard_fail=1
    continue
  fi

  if [ "$expires" -le "$WARN_THRESHOLD" ]; then
    days_left=$(((expires - NOW_EPOCH) / 86400))
    echo "WARNING: GPG key $label in $PUBKEY_FILE expires within ${WARN_DAYS} days (${days_left}d remaining, expiry_epoch=$expires)." >&2
    warn_fail=1
  fi
done <<<"$COLON_OUTPUT"

if [ "$found_pub" -eq 0 ]; then
  echo "ERROR: No primary 'pub' record found in $PUBKEY_FILE" >&2
  exit 1
fi

if [ "$hard_fail" -ne 0 ]; then
  exit 1
fi

if [ "$warn_fail" -ne 0 ]; then
  exit 2
fi

echo "OK: GPG key expiry verified for $PUBKEY_FILE (warn window: ${WARN_DAYS}d)."
exit 0
