#!/usr/bin/env bash
# ==============================================================================
# NextDNS (`infrastructure/dns`) Local Drift Detection Wrapper (STD-OT-42 / STD-CI-36 / R2-TF-07)
# ==============================================================================
# Thin compatibility wrapper around `scripts/drift.sh --module dns`.
# Snapshots R2 remote state (`--module dns`) before planning unless
# `DRIFT_SKIP_STATE_SNAPSHOT=true`.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIFT_INVOKED_AS="scripts/drift-dns.sh" exec "${SCRIPT_DIR}/drift.sh" --module dns "$@"
