#!/usr/bin/env bats
# Tests for Tailscale policy files and git-crypt encryption

load 'helpers/test_helper'

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  PROD_POLICY="${REPO_ROOT}/infrastructure/mesh/policy.hujson.tftpl"
  CI_POLICY="${REPO_ROOT}/infrastructure/mesh/policy.ci.hujson.tftpl"
}

@test "tailscale production policy template exists and has non-zero size" {
  [ -s "$PROD_POLICY" ]
}

@test "tailscale CI policy template exists, has non-zero size, and is valid JSON/HuJSON when templated" {
  [ -s "$CI_POLICY" ]
  python3 -c "import json; content = open('$CI_POLICY').read().replace('\${tag_owners}', '{}'); json.loads(content)"
}

@test "tailscale production policy template is tracked by git-crypt" {
  if command -v git-crypt >/dev/null 2>&1; then
    run git-crypt status infrastructure/mesh/policy.hujson.tftpl
    [ "$status" -eq 0 ]
    [[ "$output" =~ "encrypted" ]] || false
  else
    run git check-attr filter infrastructure/mesh/policy.hujson.tftpl
    [ "$status" -eq 0 ]
    [[ "$output" =~ "filter: git-crypt" ]] || false
  fi
}

@test "tailscale CI policy template is explicitly exempted from git-crypt" {
  if command -v git-crypt >/dev/null 2>&1; then
    run git-crypt status infrastructure/mesh/policy.ci.hujson.tftpl
    [ "$status" -eq 0 ]
    [[ "$output" =~ "not encrypted" ]] || false
  else
    run git check-attr filter infrastructure/mesh/policy.ci.hujson.tftpl
    [ "$status" -eq 0 ]
    [[ "$output" =~ "filter: unspecified" ]] || false
  fi
}

@test "tailscale CI policy template strictly uses decoy NextDNS profile ID and target" {
  run grep -E '"nextdns:000000"' "$CI_POLICY"
  [ "$status" -eq 0 ]

  run grep -E '"tag:decoy-client"' "$CI_POLICY"
  [ "$status" -eq 0 ]

  # Ensure no non-decoy nextdns attribute exists
  run python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.loads(f.read().replace('\${tag_owners}', '{}'))
for item in data.get('nodeAttrs', []):
    for attr in item.get('attr', []):
        if attr.startswith('nextdns:') and attr != 'nextdns:000000':
            sys.exit(1)
" "$CI_POLICY"
  [ "$status" -eq 0 ]
}

# --- tag:type-iot invariants (robots: tailnet reaches the robot on TCP 80 only) ---

# Prints the policy files to check: the CI policy always, the production policy
# only when this clone has it decrypted (no leading \0GITCRYPT header).
iot_policies() {
  printf '%s\n' "$CI_POLICY"
  if [ "$(head -c 10 "$PROD_POLICY" | tail -c 9 | tr -d '\000')" != "GITCRYPT" ]; then
    printf '%s\n' "$PROD_POLICY"
  fi
}

# Templates ${tag_owners} with {}, converts HuJSON (comments, trailing commas)
# to JSON, and runs the Python check expression body against `policy`.
# Only sanitized messages are printed; policy content never is.
check_iot_policy() {
  python3 - "$1" "$2" <<'PY'
import json, sys

def hujson_to_json(text):
    out, i, n, in_str = [], 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == '\\' and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
        elif c == '"':
            in_str = True
            out.append(c)
            i += 1
        elif text.startswith('//', i):
            while i < n and text[i] != '\n':
                i += 1
        elif text.startswith('/*', i):
            end = text.find('*/', i + 2)
            i = n if end < 0 else end + 2
        elif c in '}]':
            j = len(out) - 1
            while j >= 0 and out[j].isspace():
                j -= 1
            if j >= 0 and out[j] == ',':
                del out[j]
            out.append(c)
            i += 1
        else:
            out.append(c)
            i += 1
    return ''.join(out)

path, check = sys.argv[1], sys.argv[2]
with open(path) as f:
    policy = json.loads(hujson_to_json(f.read().replace('${tag_owners}', '{}')))
grants = policy.get('grants', [])
ssh = policy.get('ssh', [])
exec(check)
PY
}

@test "tag:type-iot is reachable on tcp:80 only" {
  while IFS= read -r policy; do
    run check_iot_policy "$policy" '
iot = [g for g in grants if "tag:type-iot" in g.get("dst", [])]
bad = [i for i, g in enumerate(grants) if "tag:type-iot" in g.get("dst", []) and g.get("ip") != ["tcp:80"]]
if bad:
    sys.exit("grants targeting tag:type-iot with ip other than [tcp:80]: indexes %s" % bad)
if not any("autogroup:owner" in g.get("src", []) for g in iot):
    sys.exit("no grant from autogroup:owner to tag:type-iot")
'
    [ "$status" -eq 0 ] || { echo "${policy##*/}: $output"; false; }
  done < <(iot_policies)
}

@test "tag:type-iot has no ssh rule" {
  while IFS= read -r policy; do
    run check_iot_policy "$policy" '
bad = [i for i, r in enumerate(ssh) if "tag:type-iot" in r.get("dst", [])]
if bad:
    sys.exit("ssh rules targeting tag:type-iot: indexes %s" % bad)
'
    [ "$status" -eq 0 ] || { echo "${policy##*/}: $output"; false; }
  done < <(iot_policies)
}

@test "tag:type-iot has no outbound grants" {
  while IFS= read -r policy; do
    run check_iot_policy "$policy" '
bad = [i for i, g in enumerate(grants) if "tag:type-iot" in g.get("src", [])]
if bad:
    sys.exit("grants with tag:type-iot as source: indexes %s" % bad)
'
    [ "$status" -eq 0 ] || { echo "${policy##*/}: $output"; false; }
  done < <(iot_policies)
}

# Broad rules would reach tag:type-iot without naming it, so they are banned outright.

@test "tailscale policies have no legacy acls section" {
  while IFS= read -r policy; do
    run check_iot_policy "$policy" '
if "acls" in policy:
    sys.exit("top-level acls key present; use grants that never reach tag:type-iot")
'
    [ "$status" -eq 0 ] || { echo "${policy##*/}: $output"; false; }
  done < <(iot_policies)
}

@test "tailscale grants never use * or autogroup:tagged in src or dst" {
  while IFS= read -r policy; do
    run check_iot_policy "$policy" '
broad = {"*", "autogroup:tagged"}
bad = [i for i, g in enumerate(grants) if broad & set(g.get("src", []) + g.get("dst", []))]
if bad:
    sys.exit("grants with * or autogroup:tagged in src/dst: indexes %s" % bad)
'
    [ "$status" -eq 0 ] || { echo "${policy##*/}: $output"; false; }
  done < <(iot_policies)
}

@test "tailscale ssh rules never use * or autogroup:tagged in dst" {
  while IFS= read -r policy; do
    run check_iot_policy "$policy" '
broad = {"*", "autogroup:tagged"}
bad = [i for i, r in enumerate(ssh) if broad & set(r.get("dst", []))]
if bad:
    sys.exit("ssh rules with * or autogroup:tagged in dst: indexes %s" % bad)
'
    [ "$status" -eq 0 ] || { echo "${policy##*/}: $output"; false; }
  done < <(iot_policies)
}
