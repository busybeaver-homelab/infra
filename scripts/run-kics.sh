#!/usr/bin/env bash
# scripts/run-kics.sh - Executes Checkmarx KICS scanner via Docker and sanitizes SARIF output paths.
set -euo pipefail

KICS_IMAGE="${KICS_IMAGE:-checkmarx/kics:v2.2.0}"
OUTPUT_DIR="kics-results"
OUTPUT_NAME="kics.sarif"
TARGETS="/path/infrastructure,/path/configuration"
FORMAT="sarif"
CHECK_DOCKER=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Executes Checkmarx KICS scanner against infrastructure and configuration using Docker ($KICS_IMAGE).

Options:
  -o, --output-dir DIR    Directory to write results (default: kics-results)
  -n, --output-name NAME  Filename of SARIF report (default: kics.sarif)
  -f, --format FORMAT     Report format: sarif, json, or console (default: sarif)
  -p, --path PATHS        Comma-separated scan targets (default: /path/infrastructure,/path/configuration)
  --check-docker          Check Docker availability and exit
  -h, --help              Show this help message
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o | --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -n | --output-name)
      OUTPUT_NAME="$2"
      shift 2
      ;;
    -f | --format)
      FORMAT="$2"
      shift 2
      ;;
    -p | --path)
      TARGETS="$2"
      shift 2
      ;;
    --check-docker)
      CHECK_DOCKER=true
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      echo "Run '$(basename "$0") --help' for usage." >&2
      exit 1
      ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker command not found. Please install Docker." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker daemon is not running or inaccessible." >&2
  exit 1
fi

if [ "$CHECK_DOCKER" = true ]; then
  echo "Docker is available and running."
  exit 0
fi

mkdir -p "$OUTPUT_DIR"

echo "==> Running KICS scan ($KICS_IMAGE) against $TARGETS..."
# Run KICS container with mounted working directory
set +e
docker run --rm \
  -v "${PWD}:/path" \
  "$KICS_IMAGE" scan \
  -p "$TARGETS" \
  --report-formats "$FORMAT" \
  -o "/path/$OUTPUT_DIR" \
  --output-name "$OUTPUT_NAME"
kics_exit=$?
set -e

# Sanitize container paths (/path/) to relative paths in the generated SARIF file
sarif_file="$OUTPUT_DIR/$OUTPUT_NAME"
if [ -f "$sarif_file" ]; then
  echo "==> Sanitizing container paths in $sarif_file..."
  sed -i.bak -e 's|/path/||g' -e 's|"path/|"|g' "$sarif_file" && rm -f "${sarif_file}.bak"
  echo "==> KICS SARIF generated at $sarif_file"
fi

echo "KICS finished with status $kics_exit"
exit 0
