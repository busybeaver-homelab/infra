#!/usr/bin/env bats
# Static guards for the NextDNS (infrastructure/dns) module:
# lifecycle protections, provider aliasing, SOPS mocking, and sensitive-value leak guards.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  DNS="$REPO_ROOT/infrastructure/dns"
}

# Prints the comment-stripped body of `resource "<type>" "<name>" {` up to its own closing brace.
resource_block() {
  find "$DNS" -name '*.tf' -not -path '*/.terraform/*' -exec cat {} + |
    sed -E 's/[[:space:]]*#.*$//' |
    awk -v hdr="resource \"$1\" \"$2\"" '
      !on && index($0, hdr) == 1 { on = 1; depth = 0 }
      on {
        print
        o = gsub(/\{/, "{"); c = gsub(/\}/, "}"); depth += o - c
        if (depth <= 0 && (o + c) > 0) exit
      }'
}

# Succeeds only if the block contains an active (uncommented) line matching "<key> = <value>".
lifecycle_set() {
  local key="${3%% = *}" val="${3#* = }"
  resource_block "$1" "$2" | grep -qE "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*${val}[[:space:]]*$"
}

@test "nextdns_profile resource keeps prevent_destroy lifecycle protection" {
  lifecycle_set nextdns_profile this 'prevent_destroy = var\.enable_prevent_destroy'
}

@test "enable_prevent_destroy defaults to true in root and child variables.tf" {
  for vars in "$DNS/variables.tf" "$DNS/modules/profile/variables.tf"; do
    run grep -A5 'variable "enable_prevent_destroy"' "$vars"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "default     = true" ]] || false
  done
}

@test "providers.tf and main.tf wire all five aliased providers (account_1..account_5)" {
  for acct in account_1 account_2 account_3 account_4 account_5; do
    grep -q "alias   = \"${acct}\"" "$DNS/providers.tf" || {
      echo "missing provider alias ${acct}"
      return 1
    }
    grep -q "module \"${acct}\"" "$DNS/main.tf" || {
      echo "missing module ${acct}"
      return 1
    }
    grep -q "nextdns = nextdns.${acct}" "$DNS/main.tf" || {
      echo "missing provider binding nextdns.${acct}"
      return 1
    }
  done
}

# All plaintext module sources, including generated READMEs.
dns_sources() {
  find "$DNS" \( -name '*.tf' -o -name '*.tofu' -o -name '*.tftest.hcl' -o -name '*.md' \) -not -path '*/.terraform/*'
}

leak_emails() {
  dns_sources | xargs grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | grep -vE '@example\.test$' || true
}

leak_ipv4() {
  dns_sources | xargs grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | grep -vE ':(192\.0\.2|198\.51\.100|203\.0\.113)\.[0-9]{1,3}$' || true
}

leak_ipv6() {
  dns_sources | xargs grep -oiE '([0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}|[0-9a-f]{1,4}(:[0-9a-f]{1,4})*::([0-9a-f]{1,4}(:[0-9a-f]{1,4})*)?' |
    grep -viE ':2001:db8(:|$)' || true
}

@test "no email addresses outside example.test in dns module sources" {
  run leak_emails
  [ -z "$output" ]
}

@test "no IPv4 outside RFC 5737 documentation ranges in dns module sources" {
  run leak_ipv4
  [ -z "$output" ]
}

@test "no IPv6 outside 2001:db8::/32 documentation range in dns module sources" {
  run leak_ipv6
  [ -z "$output" ]
}

@test "real NextDNS profile IDs, names, and rewrites never appear in module sources (skipped without SOPS access)" {
  local secrets="$REPO_ROOT/secrets/credentials.sops.yaml" hits="" val
  sops -d --extract '["nextdns"]["config"]' "$secrets" >/dev/null 2>&1 || skip "production SOPS not decryptable here"
  for acct in account_1 account_2 account_3 account_4 account_5; do
    val="$(sops -d --extract "[\"nextdns\"][\"config\"][\"accounts\"][\"$acct\"][\"profile_id\"]" "$secrets" 2>/dev/null || true)"
    [ -n "$val" ] && hits+="$(dns_sources | xargs grep -lF -- "$val" || true)"
    if [[ "$acct" != "account_5" ]]; then
      val="$(sops -d --extract "[\"nextdns\"][\"config\"][\"accounts\"][\"$acct\"][\"profile_name\"]" "$secrets" 2>/dev/null || true)"
      [ -n "$val" ] && hits+="$(dns_sources | xargs grep -lF -- "$val" || true)"
    fi
  done
  while IFS= read -r val; do
    [ -n "$val" ] || continue
    hits+="$(dns_sources | xargs grep -lF -- "$val" || true)"
  done < <(sops -d --extract '["nextdns"]["config"]' "$secrets" | yq eval '
    ((.shared.rewrites // [])[] | (.name, .content)),
    ((.shared.allowlist // [])[] | .id),
    ((.shared.denylist // [])[] | .id),
    ((.accounts[].overrides.extra_rewrites // [])[] | (.name, .content)),
    ((.accounts[].overrides.extra_allowlist // [])[] | .id),
    ((.accounts[].overrides.extra_denylist // [])[] | .id)
  ' - 2>/dev/null || true)
  [ -z "$hits" ]
}

@test "transient import scaffolding is removed after adoption" {
  if [[ "${ALLOW_IMPORTS_TF:-0}" == "1" ]]; then
    skip "ALLOW_IMPORTS_TF=1 set during live state import"
  fi
  [ ! -f "$DNS/imports.tf" ]
}

@test "dns guards run at commit time and on dns-only PRs" {
  run grep -A4 '^    dns-guards:' "$REPO_ROOT/lefthook.yml"
  [[ "$output" == *"tests/scripts/dns-guards.bats"* ]] || false
  run awk '/^            shell:/{on=1; next} on && /^            [a-z]+:/{exit} on' "$REPO_ROOT/.github/workflows/ci.yml"
  [[ "$output" == *"'infrastructure/dns/**'"* ]] || false
}

@test "root tofu tests never use the real sops provider" {
  for f in "$DNS"/tests/*.tftest.hcl; do
    grep -q '^mock_provider "sops"' "$f" || {
      echo "missing sops mock: ${f##*/}"
      return 1
    }
  done
}

@test "scripts/tofu-dns.sh and scripts/drift-dns.sh are executable and support --help" {
  [ -x "$REPO_ROOT/scripts/tofu-dns.sh" ]
  [ -x "$REPO_ROOT/scripts/drift-dns.sh" ]
  run "$REPO_ROOT/scripts/tofu-dns.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: scripts/tofu-dns.sh"* ]] || false
  run "$REPO_ROOT/scripts/drift-dns.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: scripts/drift-dns.sh"* ]] || false
}

@test "leak guards catch non-RFC5737 IPv4 and non-2001:db8 IPv6 in fixture" {
  DNS="$BATS_TEST_TMPDIR/leaky"
  mkdir -p "$DNS"
  printf 'ip4 = "198.18.0.10"\nip4_ok = "198.51.100.10"\n' >"$DNS/ip4.tf"
  printf 'ip6 = "2a01:4f8:1:2::3"\nip6_ok = "2001:db8::1"\n' >"$DNS/ip6.tf"
  run leak_ipv4
  [[ "$output" == *"198.18.0.10"* ]] || false
  [[ "$output" != *"198.51.100.10"* ]] || false
  run leak_ipv6
  [[ "$output" == *"2a01:4f8:1:2::3"* ]] || false
  [[ "$output" != *"2001:db8::1"* ]] || false
}
