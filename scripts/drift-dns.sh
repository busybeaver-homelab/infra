#!/usr/bin/env bash
# ==============================================================================
# NextDNS (`infrastructure/dns`) Local Drift Detection Wrapper (STD-OT-42 / STD-CI-36 / REV2-P2-7)
# ==============================================================================
# Thin compatibility wrapper around `scripts/drift.sh --module dns`.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIFT_INVOKED_AS="scripts/drift-dns.sh" exec "${SCRIPT_DIR}/drift.sh" --module dns "$@"
