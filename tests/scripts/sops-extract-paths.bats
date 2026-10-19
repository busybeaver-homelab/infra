#!/usr/bin/env bats
# Tests that every sops --extract '<path>' across scripts/*.sh,
# infrastructure/**/README.md, and readable docs/runbooks/*.md exists in the
# key tree of both canonical SOPS files (R2-OPS-05).

load 'helpers/test_helper'

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

# Verifies every --extract '<path>' in the given source files against both SOPS
# files using yq key-tree lookup (no decryption required).
verify_extract_paths_in_sources() {
  local prod_sops="$1"
  local ci_sops="$2"
  shift 2
  local sources=("$@")
  local checked=0
  local src expr yq_path prod_has ci_has

  for src in "${sources[@]}"; do
    [ -f "$src" ] || continue
    if is_git_crypt_encrypted "$src"; then
      echo "SKIP git-crypt ciphertext: $(basename "$src")"
      continue
    fi

    while IFS= read -r expr; do
      [ -z "$expr" ] && continue
      # Unescape \" inside double-quoted shell strings (e.g. scripts/bootstrap.sh)
      expr="${expr//\\\"/\"}"
      # Skip documentation placeholders such as ["<domain>"]["config"]
      if [[ "$expr" == *"<"*">"* ]]; then
        continue
      fi

      yq_path=".${expr}"
      prod_has=$(yq eval "${yq_path} != null" "$prod_sops")
      if [ "$prod_has" != "true" ]; then
        echo "Missing SOPS extract path ${expr} (from ${src}) in ${prod_sops}" >&2
        return 1
      fi

      ci_has=$(yq eval "${yq_path} != null" "$ci_sops")
      if [ "$ci_has" != "true" ]; then
        echo "Missing SOPS extract path ${expr} (from ${src}) in ${ci_sops}" >&2
        return 1
      fi

      checked=$((checked + 1))
    done < <(grep -Eo -- "--extract '[^']+'" "$src" 2>/dev/null | sed -E "s/--extract '([^']+)'/\1/" || true)
  done

  if [ "$checked" -eq 0 ]; then
    echo "No --extract paths were checked" >&2
    return 1
  fi
  return 0
}

@test "every sops --extract path in scripts, infrastructure READMEs, and readable runbooks exists in both SOPS files (R2-OPS-05)" {
  local prod_sops="$REPO_ROOT/secrets/credentials.sops.yaml"
  local ci_sops="$REPO_ROOT/secrets/credentials.ci.sops.yaml"
  [ -f "$prod_sops" ]
  [ -f "$ci_sops" ]

  local sources=()
  local f
  for f in "$REPO_ROOT"/scripts/*.sh; do
    [ -f "$f" ] && sources+=("$f")
  done
  while IFS= read -r f; do
    [ -n "$f" ] && sources+=("$f")
  done < <(find "$REPO_ROOT/infrastructure" -name 'README.md' -type f | sort)
  for f in "$REPO_ROOT"/docs/runbooks/*.md; do
    [ -f "$f" ] && sources+=("$f")
  done

  run verify_extract_paths_in_sources "$prod_sops" "$ci_sops" "${sources[@]}"
  if [ "$status" -ne 0 ]; then
    echo "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "sops --extract key-path check fails when a referenced path is missing from a synthetic SOPS file (R2-OPS-05)" {
  local syn_prod="$BATS_TMPDIR/prod.sops.yaml"
  local syn_ci="$BATS_TMPDIR/ci.sops.yaml"
  local syn_script="$BATS_TMPDIR/sample.sh"

  cat <<'EOF' >"$syn_prod"
cloudflare:
  api_token: "ENC[AES256_GCM,data:aaaa,iv:bbbb,tag:cccc,type:str]"
sops:
  version: "3.9.0"
EOF
  cp "$syn_prod" "$syn_ci"

  cat <<'EOF' >"$syn_script"
#!/usr/bin/env bash
sops -d --extract '["cloudflare"]["api_token"]' secrets/credentials.sops.yaml
sops -d --extract '["cloudflare"]["missing_leaf"]' secrets/credentials.sops.yaml
EOF

  run verify_extract_paths_in_sources "$syn_prod" "$syn_ci" "$syn_script"
  [ "$status" -eq 1 ]
  [[ "$output" == *'["cloudflare"]["missing_leaf"]'* ]]
}

@test "sops --extract key-path check skips git-crypt ciphertext runbooks and reports the skip" {
  local syn_prod="$BATS_TMPDIR/prod.sops.yaml"
  local syn_ci="$BATS_TMPDIR/ci.sops.yaml"
  local syn_script="$BATS_TMPDIR/sample.sh"
  local enc_runbook="$BATS_TMPDIR/encrypted-runbook.md"

  cat <<'EOF' >"$syn_prod"
cloudflare:
  api_token: "ENC[AES256_GCM,data:aaaa,iv:bbbb,tag:cccc,type:str]"
sops:
  version: "3.9.0"
EOF
  cp "$syn_prod" "$syn_ci"

  cat <<'EOF' >"$syn_script"
#!/usr/bin/env bash
sops -d --extract '["cloudflare"]["api_token"]' secrets/credentials.sops.yaml
EOF

  # Write a git-crypt header (\0GITCRYPT\0) followed by a bogus --extract path
  printf '\x00GITCRYPT\x00--extract '\''["nonexistent"]["key"]'\''\n' >"$enc_runbook"

  run verify_extract_paths_in_sources "$syn_prod" "$syn_ci" "$syn_script" "$enc_runbook"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP git-crypt ciphertext: encrypted-runbook.md"* ]]
}
