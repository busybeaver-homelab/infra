#!/usr/bin/env bash
# Rotate the OpenTofu state encryption passphrase for one or more root modules.
#
# OpenTofu stores the pbkdf2 salt in the state metadata under the key provider's NAME
# (key_provider.pbkdf2.<name>). A rotation therefore needs a NEW provider name: the old
# name keeps the old passphrase as a fallback, the new name encrypts with the new one.
# For each module this script:
#   1. builds a throwaway config (backend.tf copy + rotation encryption) in a mktemp dir,
#   2. reads the state through the fallback and pushes it back encrypted with the new key
#      (state pull | state push -: no provider credentials, no refresh, serial unchanged),
#   3. proves the new passphrase alone can read the state,
#   4. renames the provider in infrastructure/<module>/encryption.tf (state_passphrase ->
#      state_passphrase_v2 -> _v3 ...). Commit that rename before anyone runs tofu again.
#
# Usage: scripts/rotate-state-passphrase.sh [--yes] <module>... | --all
#   TF_VAR_state_encryption_passphrase           new passphrase (required, >= 32 chars)
#   TF_VAR_state_encryption_passphrase_previous  current passphrase (required)
#   TOFU_BACKEND_ENDPOINT                        passed as -backend-config=endpoint=... (R2)
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY    R2 backend credentials, as for any tofu run
#   INFRA_DIR                                    overrides infrastructure/ (tests)
# Passphrases are read from the environment only and never printed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="${INFRA_DIR:-$REPO_ROOT/infrastructure}"

# Prints the name of the single pbkdf2 key provider in an encryption.tf; fails otherwise.
current_provider_name() {
  local names
  names="$(sed -nE 's/^[[:space:]]*key_provider "pbkdf2" "([A-Za-z0-9_]+)".*/\1/p' "$1")"
  if [[ -z "$names" ]]; then
    echo "ERROR: no pbkdf2 key provider in $1" >&2
    return 1
  fi
  if [[ "$(printf '%s\n' "$names" | wc -l | tr -d ' ')" != "1" ]]; then
    echo "ERROR: more than one pbkdf2 key provider in $1 (rotation already in progress?)" >&2
    return 1
  fi
  printf '%s\n' "$names"
}

# state_passphrase -> state_passphrase_v2, state_passphrase_v2 -> state_passphrase_v3
next_provider_name() {
  if [[ "$1" =~ ^(.*)_v([0-9]+)$ ]]; then
    printf '%s_v%d\n' "${BASH_REMATCH[1]}" "$((BASH_REMATCH[2] + 1))"
  else
    printf '%s_v2\n' "$1"
  fi
}

# Prints the key_provider block <name> from <file>, with its passphrase bound to <var>.
provider_block() {
  local file="$1" name="$2" new_name="$3" var="$4"
  awk -v name="$name" -v new_name="$new_name" -v var="$var" '
    $0 ~ "key_provider \"pbkdf2\" \"" name "\"" { inside = 1; sub("\"" name "\"", "\"" new_name "\"") }
    inside && /passphrase[[:space:]]*=/ { sub(/=.*/, "= var." var) }
    inside { print }
    inside && /^[[:space:]]*}[[:space:]]*$/ { exit }
  ' "$file"
}

# Writes the temporary rotation config: new key primary, old key (old name) as fallback.
render_rotation_config() {
  local enc="$1" old="$2" new="$3"
  cat <<EOF
variable "state_encryption_passphrase" {
  type      = string
  sensitive = true
}

variable "state_encryption_passphrase_previous" {
  type      = string
  sensitive = true
}

terraform {
  encryption {
$(provider_block "$enc" "$old" "$old" state_encryption_passphrase_previous)

$(provider_block "$enc" "$old" "$new" state_encryption_passphrase)

    method "aes_gcm" "rotation_previous" {
      keys = key_provider.pbkdf2.${old}
    }

    method "aes_gcm" "rotation_current" {
      keys = key_provider.pbkdf2.${new}
    }

    state {
      method   = method.aes_gcm.rotation_current
      enforced = true

      fallback {
        method = method.aes_gcm.rotation_previous
      }
    }
  }
}
EOF
}

# Writes the post-rotation verification config: new key only, no fallback.
render_verify_config() {
  local enc="$1" old="$2" new="$3"
  cat <<EOF
variable "state_encryption_passphrase" {
  type      = string
  sensitive = true
}

terraform {
  encryption {
$(provider_block "$enc" "$old" "$new" state_encryption_passphrase)

    method "aes_gcm" "rotation_current" {
      keys = key_provider.pbkdf2.${new}
    }

    state {
      method   = method.aes_gcm.rotation_current
      enforced = true
    }
  }
}
EOF
}

rename_provider() {
  local enc="$1" old="$2" new="$3" tmp
  tmp="$(mktemp "${enc}.XXXXXX")"
  sed -E "s/key_provider \"pbkdf2\" \"${old}\"/key_provider \"pbkdf2\" \"${new}\"/; s/key_provider\.pbkdf2\.${old}([^A-Za-z0-9_]|\$)/key_provider.pbkdf2.${new}\1/g" "$enc" >"$tmp"
  mv "$tmp" "$enc"
}

# Runs in a subshell so the EXIT trap removes the work dir on every path.
rotate_module() (
  local module="$1" dir="$INFRA_DIR/$1" old new work state_json
  local -a backend_args=()
  [[ -f "$dir/encryption.tf" && -f "$dir/backend.tf" ]] || {
    echo "ERROR: $module: encryption.tf or backend.tf missing in $dir" >&2
    return 1
  }
  old="$(current_provider_name "$dir/encryption.tf")"
  new="$(next_provider_name "$old")"
  [[ -n "${TOFU_BACKEND_ENDPOINT:-}" ]] && backend_args=("-backend-config=endpoint=${TOFU_BACKEND_ENDPOINT}")

  work="$(mktemp -d)"
  chmod 700 "$work"
  trap 'rm -rf "$work"' EXIT
  cp "$dir/backend.tf" "$work/backend.tf"
  render_rotation_config "$dir/encryption.tf" "$old" "$new" >"$work/encryption.tf"

  # init already reads the state, so a wrong passphrase surfaces here.
  tofu -chdir="$work" init -input=false -no-color ${backend_args[@]+"${backend_args[@]}"} >"$work/init.log" 2>&1 || {
    if grep -q 'decryption failed' "$work/init.log"; then
      echo "ERROR: $module: cannot read the state with either passphrase; nothing was changed" >&2
      return 1
    fi
    echo "ERROR: $module: tofu init failed" >&2
    grep -E 'Error' -A4 "$work/init.log" >&2 || true
    return 1
  }

  # Plaintext state stays in memory only; it is never written to disk or printed.
  if ! state_json="$(tofu -chdir="$work" state pull 2>"$work/pull.err")"; then
    echo "ERROR: $module: cannot read the state with either passphrase" >&2
    grep -E 'Error' -A3 "$work/pull.err" >&2 || true
    return 1
  fi

  if [[ -z "$state_json" ]]; then
    echo "$module: no remote state yet; nothing to re-encrypt"
  else
    printf '%s' "$state_json" | tofu -chdir="$work" state push - >/dev/null 2>"$work/push.err" || {
      echo "ERROR: $module: state push failed; the state is unchanged" >&2
      grep -E 'Error' -A3 "$work/push.err" >&2 || true
      return 1
    }
    render_verify_config "$dir/encryption.tf" "$old" "$new" >"$work/encryption.tf"
    env -u TF_VAR_state_encryption_passphrase_previous \
      tofu -chdir="$work" state pull >/dev/null 2>&1 || {
      echo "ERROR: $module: the new passphrase alone cannot read the pushed state" >&2
      return 1
    }
    echo "$module: state re-encrypted (key_provider.pbkdf2.${old} -> ${new})"
  fi
  unset state_json

  rename_provider "$dir/encryption.tf" "$old" "$new"
  echo "$module: renamed the key provider in encryption.tf to ${new}"
)

main() {
  local assume_yes=0 module
  local -a modules=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) assume_yes=1 ;;
      --all)
        for module in "$INFRA_DIR"/*/; do
          [[ -f "$module/encryption.tf" ]] && modules+=("$(basename "$module")")
        done
        ;;
      -h | --help)
        sed -n '2,23p' "$0"
        return 0
        ;;
      -*)
        echo "Unknown argument: $1" >&2
        return 1
        ;;
      *) modules+=("$1") ;;
    esac
    shift
  done

  [[ ${#modules[@]} -gt 0 ]] || {
    echo "Usage: $0 [--yes] <module>... | --all" >&2
    return 1
  }
  if [[ -z "${TF_VAR_state_encryption_passphrase:-}" || -z "${TF_VAR_state_encryption_passphrase_previous:-}" ]]; then
    echo "ERROR: export TF_VAR_state_encryption_passphrase (new) and TF_VAR_state_encryption_passphrase_previous (current) from SOPS first" >&2
    return 1
  fi
  if [[ ${#TF_VAR_state_encryption_passphrase} -lt 32 ]]; then
    echo "ERROR: the new passphrase must be at least 32 characters" >&2
    return 1
  fi
  if [[ "$TF_VAR_state_encryption_passphrase" == "$TF_VAR_state_encryption_passphrase_previous" ]]; then
    echo "ERROR: the new passphrase equals the current one" >&2
    return 1
  fi
  command -v tofu >/dev/null || {
    echo "ERROR: tofu not found on PATH (run via mise exec --)" >&2
    return 1
  }

  if [[ "$assume_yes" -ne 1 ]]; then
    echo "This re-encrypts the REMOTE state of: ${modules[*]}"
    read -r -p "Type 'rotate' to continue: " answer
    [[ "$answer" == "rotate" ]] || {
      echo "Aborted."
      return 1
    }
  fi

  for module in "${modules[@]}"; do
    rotate_module "$module"
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
