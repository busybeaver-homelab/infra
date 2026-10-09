#!/usr/bin/env bats
# Static guards for the Cloudflare module: lifecycle protections must never be removed silently.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CF="$REPO_ROOT/infrastructure/cloudflare"
}

# Prints the body of `resource "<type>" "<name>" {` up to the next top-level resource.
resource_block() {
  awk -v hdr="resource \"$1\" \"$2\"" '
    index($0, hdr) == 1 { on = 1 }
    on && /^resource "/ && index($0, hdr) != 1 { exit }
    on { print }
  ' "$CF"/*.tf "$CF"/modules/zone/*.tf
}

@test "frozen account tokens keep prevent_destroy and ignore_changes = all" {
  run resource_block cloudflare_account_token frozen
  [ -n "$output" ]
  [[ "$output" == *"prevent_destroy = true"* ]]
  [[ "$output" == *"ignore_changes  = all"* ]]
}

@test "frozen account member keeps prevent_destroy and ignore_changes = all" {
  run resource_block cloudflare_account_member frozen
  [ -n "$output" ]
  [[ "$output" == *"prevent_destroy = true"* ]]
  [[ "$output" == *"ignore_changes  = all"* ]]
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
    run resource_block $spec
    [ -n "$output" ] || { echo "missing: $spec"; return 1; }
    [[ "$output" == *"prevent_destroy = true"* ]] || { echo "unguarded: $spec"; return 1; }
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
