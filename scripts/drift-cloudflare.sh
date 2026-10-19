#!/usr/bin/env bash
# ==============================================================================
# Cloudflare Local Drift Detection Wrapper (STD-OT-42 / STD-CI-36 / R2-TF-07)
# ==============================================================================
# Thin compatibility wrapper around `scripts/drift.sh --module cloudflare`.
# Snapshots R2 remote state (`--module cloudflare`) before planning unless
# `DRIFT_SKIP_STATE_SNAPSHOT=true`.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIFT_INVOKED_AS="scripts/drift-cloudflare.sh" exec "${SCRIPT_DIR}/drift.sh" --module cloudflare "$@"
