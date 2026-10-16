#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORKFLOW="$REPO_ROOT/.github/workflows/drift-detection.yml"
}

@test "drift detection workflow file exists and is valid YAML" {
  [ -f "$WORKFLOW" ]
  run yq eval '.' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "drift detection workflow is manual-only until local drift:all replaces it (REV2-P0-7)" {
  run yq eval '.on.schedule' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]

  run yq eval '.on | keys | join(",")' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "workflow_dispatch" ]
}

@test "drift detection workflow defines matrix across the 7 CI-plannable modules" {
  for mod in oci gcp azure homelab github monitoring mesh; do
    run yq eval ".jobs.drift-detect.strategy.matrix.module[] | select(. == \"$mod\")" "$WORKFLOW"
    [ "$status" -eq 0 ]
    [ "$output" = "$mod" ]
  done
}

@test "cloudflare drift runs locally, not in the CI matrix (needs production SOPS)" {
  run yq eval '.jobs.drift-detect.strategy.matrix.module[] | select(. == "cloudflare")' "$WORKFLOW"
  [ -z "$output" ]
  run grep -E 'mise run drift:cloudflare' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "drift detection workflow configures provider plugin caching" {
  run grep -E "actions/cache" "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -E "tofu-plugins" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "drift detection workflow uses tofu plan with detailed-exitcode and readonly lockfile" {
  run grep -E "tofu plan.*-detailed-exitcode" "$WORKFLOW"
  [ "$status" -eq 0 ]

  # -lockfile is an init flag; on plan it is an error that failed every run.
  run grep -E "tofu init.*-lockfile=readonly" "$WORKFLOW"
  [ "$status" -eq 0 ]
  run grep -E "tofu plan.*-lockfile" "$WORKFLOW"
  [ "$status" -ne 0 ]
}

@test "drift detection workflow exports and masks opentofu r2 backend credentials" {
  run grep -E "opentofu\.cloudflare_r2_access_key_id" "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -E "::add-mask::" "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -E "AWS_ACCESS_KEY_ID" "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -E "AWS_SECRET_ACCESS_KEY" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "drift detection workflow exports and masks opentofu state encryption passphrase" {
  run grep -E "opentofu\.state_encryption_passphrase" "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -E "TF_VAR_state_encryption_passphrase" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "drift detection workflow never prints plan or log text and uses env indirection" {
  run grep -nE 'cat .*(drift|plan|RUNNER_TEMP)' "$WORKFLOW"
  [ "$status" -ne 0 ]
  # No ${{ }} expressions inside run: blocks (template injection hygiene).
  run yq eval '[.jobs.drift-detect.steps[].run | select(. != null) | select(test("[$][{][{]"))] | length' "$WORKFLOW"
  [ "$output" = "0" ]
}

# Runs the real "Check Infrastructure Drift" step against a stub tofu that prints marker
# text and exits with STUB_RC; the step summary must never contain that text.
run_drift_step() {
  local stub="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$stub"
  cat >"$stub/mise" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "exec" ] && shift
[ "$1" = "--" ] && shift
case "$1 $2" in
  "tofu plan")
    echo "PLAN-TEXT-MARKER secret_attribute = \"do-not-print\""
    echo "Error: Synthetic failure headline"
    echo "  detail line with VALUE-MARKER"
    exit "${STUB_RC}"
    ;;
  "tofu show")
    echo '{"resource_changes":[
      {"address":"a.ADDRESS-MARKER","change":{"actions":["create"]}},
      {"address":"b.x","change":{"actions":["update"]}},
      {"address":"c.x","change":{"actions":["delete","create"]}},
      {"address":"d.x","change":{"actions":["no-op"]}}]}'
    ;;
esac
EOF
  chmod +x "$stub/mise"
  yq eval '.jobs.drift-detect.steps[] | select(.id == "drift") | .run' "$WORKFLOW" >"${BATS_TEST_TMPDIR}/step.sh"
  export RUNNER_TEMP="${BATS_TEST_TMPDIR}" GITHUB_STEP_SUMMARY="${BATS_TEST_TMPDIR}/summary.md" MODULE=github
  : >"$GITHUB_STEP_SUMMARY"
  (cd "$REPO_ROOT" && PATH="$stub:$PATH" STUB_RC="$1" bash -e "${BATS_TEST_TMPDIR}/step.sh")
}

@test "drift step reports counts only when drift is detected" {
  run run_drift_step 2
  [ "$status" -eq 2 ]
  run cat "${BATS_TEST_TMPDIR}/summary.md"
  [[ "$output" == *"1 to add, 1 to change, 1 to replace, 0 to destroy"* ]] || false
  [[ "$output" != *MARKER* ]] || false
  [[ "$output" != *do-not-print* ]] || false
  [ ! -e "${BATS_TEST_TMPDIR}/drift.tfplan" ]
  [ ! -e "${BATS_TEST_TMPDIR}/drift_plan.log" ]
}

@test "drift step reports only error headlines on failure" {
  run run_drift_step 1
  [ "$status" -eq 1 ]
  [[ "$output" != *MARKER* ]] || false
  run cat "${BATS_TEST_TMPDIR}/summary.md"
  [[ "$output" == *"- Error: Synthetic failure headline"* ]] || false
  [[ "$output" != *MARKER* ]] || false
}

@test "drift step reports a clean module without output" {
  run run_drift_step 0
  [ "$status" -eq 0 ]
  [[ "$output" != *MARKER* ]] || false
  run cat "${BATS_TEST_TMPDIR}/summary.md"
  [[ "$output" == *"No drift detected for github"* ]] || false
}

@test "drift detection workflow configures Tailscale OAuth credentials for mesh and exposes unified drift:all" {
  run grep -F 'TAILSCALE_OAUTH_CLIENT_ID' "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F 'TAILSCALE_OAUTH_CLIENT_SECRET' "$WORKFLOW"
  [ "$status" -eq 0 ]

  [ -x "$REPO_ROOT/scripts/drift.sh" ]

  run grep -E '^\[tasks\."drift:all"\]' "$REPO_ROOT/mise.toml"
  [ "$status" -eq 0 ]
}
