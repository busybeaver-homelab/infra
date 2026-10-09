#!/usr/bin/env bats
# Static guards for the Cloudflare module: lifecycle protections must never be removed silently.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CF="$REPO_ROOT/infrastructure/cloudflare"
}

# Prints the comment-stripped body of `resource "<type>" "<name>" {` up to its own closing brace.
resource_block() {
  find "$CF" -name '*.tf' -not -path '*/.terraform/*' -exec cat {} + |
    sed -E 's/[[:space:]]*#.*$//' |
    awk -v hdr="resource \"$1\" \"$2\"" '
      !on && index($0, hdr) == 1 { on = 1; depth = 0 }
      on {
        print
        o = gsub(/\{/, "{"); c = gsub(/\}/, "}"); depth += o - c
        if (depth <= 0 && (o + c) > 0) exit
      }'
}

# Succeeds only if the block contains an active (uncommented) line exactly "<key> = <value>".
lifecycle_set() {
  local key="${3%% = *}" val="${3#* = }"
  resource_block "$1" "$2" | grep -qE "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*${val}[[:space:]]*$"
}

@test "frozen account tokens keep prevent_destroy and ignore_changes = all" {
  lifecycle_set cloudflare_account_token frozen 'prevent_destroy = true'
  lifecycle_set cloudflare_account_token frozen 'ignore_changes = all'
}

@test "frozen account member keeps prevent_destroy and ignore_changes = all" {
  lifecycle_set cloudflare_account_member frozen 'prevent_destroy = true'
  lifecycle_set cloudflare_account_member frozen 'ignore_changes = all'
}

@test "frozen tokens cover exactly grafana, r2_state and terraform" {
  run grep -cE '^\s+(grafana|r2_state|terraform)\s+= "' "$CF/iam_frozen.tf"
  [ "$output" -eq 3 ]
}

@test "frozen token permissions are sourced from SOPS, not plaintext" {
  [ ! -f "$CF/iam_frozen_permissions.tf" ]
  run grep -c 'local.cf.iam.tokens\[each.key\].policies' "$CF/iam_frozen.tf"
  [ "$output" -eq 1 ]
}

@test "critical resources keep prevent_destroy" {
  for spec in "cloudflare_account this" "cloudflare_zero_trust_organization this" \
    "cloudflare_r2_bucket tfstate" "cloudflare_r2_bucket backups_dr" \
    "cloudflare_zone this" "cloudflare_zone_dnssec this"; do
    # shellcheck disable=SC2086
    lifecycle_set $spec 'prevent_destroy = true' || { echo "unguarded or missing: $spec"; return 1; }
  done
}

cf_sources() {
  find "$CF" \( -name '*.tf' -o -name '*.tftest.hcl' \) -not -path '*/.terraform/*'
}

@test "no 32-hex Cloudflare IDs in plaintext module sources (except zero-padded decoys)" {
  run bash -c "$(declare -f cf_sources); CF='$CF'; cf_sources | xargs grep -nE '[0-9a-f]{32}' | grep -vE '\"0{24}[0-9a-f]{8}\"'"
  [ -z "$output" ]
}

@test "no email addresses outside example.test in module sources" {
  run bash -c "$(declare -f cf_sources); CF='$CF'; cf_sources | xargs grep -noE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | grep -v '@example\.test'"
  [ -z "$output" ]
}

@test "no public IPv4 outside RFC 5737 documentation ranges in module sources" {
  run bash -c "$(declare -f cf_sources); CF='$CF'; cf_sources | xargs grep -noE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | grep -vE ':(192\.0\.2|198\.51\.100|203\.0\.113)\.[0-9]{1,3}$'"
  [ -z "$output" ]
}

@test "real zone name never appears in module sources (skipped without SOPS access)" {
  zone_name="$(sops -d --extract '["cloudflare"]["config"]["zones"]["primary"]["name"]' "$REPO_ROOT/secrets/credentials.sops.yaml" 2>/dev/null)" || skip "production SOPS not decryptable here"
  [ -n "$zone_name" ] || skip "zone name not set"
  run bash -c "$(declare -f cf_sources); CF='$CF'; cf_sources | xargs grep -lF -- '$zone_name'"
  [ -z "$output" ]
}

@test "transient import scaffolding is removed after adoption" {
  [ ! -f "$CF/imports.tf" ]
  run grep -n 'run_imports' "$CF/variables.tf" "$CF/tests/cloudflare.tftest.hcl"
  [ "$status" -ne 0 ]
}

@test "cloudflare guards run at commit time and on cloudflare-only PRs" {
  run grep -A4 '^    cloudflare-guards:' "$REPO_ROOT/lefthook.yml"
  [[ "$output" == *"tests/scripts/cloudflare-guards.bats"* ]]
  run awk '/^            shell:/{on=1; next} on && /^            [a-z]+:/{exit} on' "$REPO_ROOT/.github/workflows/ci.yml"
  [[ "$output" == *"'infrastructure/cloudflare/**'"* ]]
}

@test "lifecycle guard rejects commented-out or weakened settings" {
  CF="$BATS_TEST_TMPDIR/cf"
  mkdir -p "$CF"
  cat >"$CF/fixture.tf" <<'HCL'
resource "cloudflare_account_token" "frozen" {
  lifecycle {
    # prevent_destroy = true
    ignore_changes = [name] # ignore_changes  = all
  }
}

resource "cloudflare_account_member" "frozen" {
  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}
HCL
  run lifecycle_set cloudflare_account_token frozen 'prevent_destroy = true'
  [ "$status" -ne 0 ]
  run lifecycle_set cloudflare_account_token frozen 'ignore_changes = all'
  [ "$status" -ne 0 ]
  run lifecycle_set cloudflare_account_member frozen 'prevent_destroy = true'
  [ "$status" -eq 0 ]
  run lifecycle_set cloudflare_account_member frozen 'ignore_changes = all'
  [ "$status" -eq 0 ]
}

@test "resource block ends at its own closing brace" {
  CF="$BATS_TEST_TMPDIR/cf2"
  mkdir -p "$CF"
  printf 'resource "a" "b" {\n  x = 1\n}\n\ncheck "c" {\n  prevent_destroy = true\n}\n\nresource "d" "e" {\n  prevent_destroy = true\n}\n' >"$CF/fixture.tf"
  run lifecycle_set a b 'prevent_destroy = true'
  [ "$status" -eq 1 ]
  run lifecycle_set d e 'prevent_destroy = true'
  [ "$status" -eq 0 ]
}

@test "root tofu tests never use the real sops provider" {
  # A root-module test without a sops mock would decrypt production SOPS (locally) via data.sops_file.
  for f in "$CF"/tests/*.tftest.hcl; do
    runs=$(grep -c '^run "' "$f" || true)
    module_runs=$(grep -c 'module { source = "./modules/zone" }' "$f" || true)
    if [ "$runs" -ne "$module_runs" ]; then
      grep -q '^mock_provider "sops"' "$f" || { echo "missing sops mock: ${f##*/}"; return 1; }
    fi
  done
}
