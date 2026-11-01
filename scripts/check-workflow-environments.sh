#!/usr/bin/env bash
set -euo pipefail

# Policy check for protected GitHub Actions environments (design 4.7): only the backup
# workflows may declare the 'ops' or 'backup' environment, and no job may select its
# environment through an expression, so owner review of those workflows is what guards
# the secrets stored in them. Remote reusable workflows are refused because a called
# workflow resolves environments against this repository but is not checked here; local
# calls into the allowlisted backup workflows are refused outside the allowlist.
#
# Usage: scripts/check-workflow-environments.sh [--workflows-dir DIR]
# Exit codes:
#   0 - No violation found
#   1 - A workflow outside the allowlist uses a protected environment or calls a backup
#       workflow, a job's environment contains an expression, or a job calls a remote
#       reusable workflow
#   2 - Fail closed: missing or empty directory, unreadable or unparsable YAML, no jobs mapping

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"
ALLOWED_FILES=(backup-dr-copy.yml backup-prune.yml)
PROTECTED_ENVS=(ops backup)

# Prints "<job>\t<environment name>" for every job that declares an environment, with
# YAML aliases and merge keys resolved. Map-form environments yield their name.
JOB_ENV_EXPR='explode(.) | .jobs | to_entries | .[] | select(.value.environment != null) | .key + "\t" + (.value.environment | (if tag == "!!map" then (.name // "") else . end) | to_string)'
# Prints "<job>\t<uses>" for every job that calls a reusable workflow.
JOB_USES_EXPR='explode(.) | .jobs | to_entries | .[] | select(.value.uses != null) | .key + "\t" + (.value.uses | to_string)'

usage() {
  sed -n '4,17p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

fail_closed() {
  echo "ERROR: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workflows-dir)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "ERROR: --workflows-dir requires a value." >&2
        usage 1 >&2
      fi
      WORKFLOWS_DIR="$2"
      shift 2
      ;;
    -h | --help)
      usage 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage 1 >&2
      ;;
  esac
done

[[ -d "$WORKFLOWS_DIR" ]] || fail_closed "Workflows directory not found: $WORKFLOWS_DIR"

shopt -s nullglob
files=("$WORKFLOWS_DIR"/*.yml "$WORKFLOWS_DIR"/*.yaml)
shopt -u nullglob
[[ ${#files[@]} -gt 0 ]] || fail_closed "No workflow files (*.yml, *.yaml) found in: $WORKFLOWS_DIR"

violations=()

for file in "${files[@]}"; do
  base="$(basename "$file")"

  jobs_tag="$(yq eval '.jobs | tag' "$file" 2>/dev/null)" || fail_closed "Cannot parse workflow YAML: $base"
  [[ "$jobs_tag" == "!!map" ]] || fail_closed "Workflow has no jobs mapping: $base"
  rows="$(yq eval -r "$JOB_ENV_EXPR" "$file" 2>/dev/null)" || fail_closed "Cannot evaluate job environments: $base"
  uses_rows="$(yq eval -r "$JOB_USES_EXPR" "$file" 2>/dev/null)" || fail_closed "Cannot evaluate reusable workflow calls: $base"

  allowed=false
  for allowed_file in "${ALLOWED_FILES[@]}"; do
    [[ "$base" == "$allowed_file" ]] && allowed=true
  done

  while IFS=$'\t' read -r job env_name; do
    [[ -n "$job" ]] || continue
    # shellcheck disable=SC2016 # literal expression opener, not a shell expansion
    if [[ "$env_name" == *'${{'* ]]; then
      violations+=("$base:$job declares an environment through an expression")
      continue
    fi
    # Environment names are case-insensitive on GitHub; ignore surrounding whitespace.
    normalized="$(printf '%s' "$env_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    for protected in "${PROTECTED_ENVS[@]}"; do
      if [[ "$normalized" == "$protected" && "$allowed" != "true" ]]; then
        violations+=("$base:$job uses protected environment '$protected' outside the allowlist")
      fi
    done
  done <<<"$rows"

  while IFS=$'\t' read -r job target; do
    [[ -n "$job" ]] || continue
    if [[ "$target" != ./* ]]; then
      violations+=("$base:$job calls a remote reusable workflow")
      continue
    fi
    for allowed_file in "${ALLOWED_FILES[@]}"; do
      if [[ "$(basename "$target")" == "$allowed_file" && "$allowed" != "true" ]]; then
        violations+=("$base:$job calls the allowlisted workflow $allowed_file outside the allowlist")
      fi
    done
  done <<<"$uses_rows"
done

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "ERROR: Workflow environment policy violations (see design 4.7):" >&2
  printf '  %s\n' "${violations[@]}" >&2
  echo "Allowlisted for ops/backup: ${ALLOWED_FILES[*]}" >&2
  exit 1
fi

echo "Workflow environment policy satisfied (${#files[@]} workflow files checked)."
