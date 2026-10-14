#!/usr/bin/env bats
# Tests for .gitattributes encryption and diff rules

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  GITATTR="${REPO_ROOT}/.gitattributes"
}

@test ".gitattributes contains mandatory git-crypt filter for tailscale policy template" {
  grep -q "infrastructure/mesh/policy.hujson.tftpl filter=git-crypt diff=git-crypt" "$GITATTR"
}

@test ".gitattributes contains mandatory exemption for tailscale policy CI template decoy" {
  grep -q "infrastructure/mesh/policy.ci.hujson.tftpl !filter !diff" "$GITATTR"
}

@test ".gitattributes contains all root encryption rules intact" {
  grep -q "docs/\*\* filter=git-crypt diff=git-crypt" "$GITATTR"
  grep -q "backups/\*\* filter=git-crypt diff=git-crypt" "$GITATTR"
  grep -q "secrets/credentials.sops.yaml -diff merge=binary" "$GITATTR"
  grep -q "secrets/credentials.ci.sops.yaml diff=sops merge=binary" "$GITATTR"
  grep -q "\.gitattributes \!filter \!diff" "$GITATTR"
}

@test "all paths referenced in .gitattributes exist or match expected repository structure" {
  [ -f "${REPO_ROOT}/secrets/credentials.ci.sops.yaml" ]
  [ -f "${REPO_ROOT}/secrets/credentials.sops.yaml" ]
  [ -d "${REPO_ROOT}/docs" ]
  [ -d "${REPO_ROOT}/backups" ]
  [ -f "${REPO_ROOT}/.gitattributes" ]
}
