#!/usr/bin/env bats
# Tests for .github/workflows/ci.yml and .github/actions/setup-environment

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"
  ACTION="$REPO_ROOT/.github/actions/setup-environment/action.yml"
}

@test "setup-environment composite action file exists and is valid YAML" {
  [ -f "$ACTION" ]
  run yq eval '.' "$ACTION"
  [ "$status" -eq 0 ]
}

@test "setup-environment composite action defines inputs with default false" {
  run yq eval '.inputs.python.default' "$ACTION"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run yq eval '.inputs.tflint.default' "$ACTION"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run yq eval '.inputs.galaxy.default' "$ACTION"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "setup-environment composite action installs mise with cache true" {
  run yq eval '.runs.steps[] | select(.uses == "*jdx/mise-action*") | .with.cache' "$ACTION"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "ci.yml exists and is valid YAML" {
  [ -f "$WORKFLOW" ]
  run yq eval '.' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "ci.yml does not contain deprecated build-apps job" {
  run yq eval '.jobs.build-apps' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "ci.yml uses setup-environment composite action" {
  run grep -F "uses: $/.github/actions/setup-environment" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "ci.yml ci-gate does not depend on build-apps" {
  run yq eval '.jobs.ci-gate.needs[] | select(. == "build-apps")' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "apps/sample-app is pruned and apps/README.md documents architecture boundary" {
  [ ! -d "$REPO_ROOT/apps/sample-app" ]
  [ -f "$REPO_ROOT/apps/README.md" ]

  run grep -E "Docker Compose Stacks" "$REPO_ROOT/apps/README.md"
  [ "$status" -eq 0 ]

  run grep -E "Cloudflare Workers" "$REPO_ROOT/apps/README.md"
  [ "$status" -eq 0 ]
}

@test "mise check:general task runs cleanly with --no-error-on-unmatched-pattern" {
  run mise run check:general
  [ "$status" -eq 0 ]
}

@test "ci.yml does not contain redundant security-scan job" {
  run yq eval '.jobs.security-scan' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}
@test "ci.yml ci-gate does not depend on security-scan" {
  run yq eval '.jobs.ci-gate.needs[] | select(. == "security-scan")' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mise tasks include granular and aggregate security scanning tasks" {
  run mise tasks
  [ "$status" -eq 0 ]
  [[ "$output" =~ "check:security" ]] || false
  [[ "$output" =~ "check:security:checkov" ]] || false
  [[ "$output" =~ "check:security:kics" ]] || false
  [[ "$output" =~ "check:security:trivy" ]] || false
}

@test "codeql.yml defines multi-engine security scanning with distinct categories" {
  run yq eval '.jobs.analyze-iac-and-scripts.steps[] | select(.uses == "*upload-sarif*") | .with.category' "$REPO_ROOT/.github/workflows/codeql.yml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "checkov" ]] || false
  [[ "$output" =~ "kics" ]] || false
  [[ "$output" =~ "trivy-iac" ]] || false
  [[ "$output" =~ "trivy-fs" ]] || false
  [[ "$output" =~ "zizmor" ]] || false
  [[ "$output" =~ "shellcheck" ]] || false
}

@test "ci.yml shell-bats job sets python and galaxy true in setup-environment" {
  run yq eval '.jobs.shell-bats.steps[] | select(.uses == "$/.github/actions/setup-environment" or .uses == "./.github/actions/setup-environment") | .with.python' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run yq eval '.jobs.shell-bats.steps[] | select(.uses == "$/.github/actions/setup-environment" or .uses == "./.github/actions/setup-environment") | .with.galaxy' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "ci.yml lint-format job sets python, galaxy, and tflint true in setup-environment" {
  run yq eval '.jobs.lint-format.steps[] | select(.uses == "$/.github/actions/setup-environment" or .uses == "./.github/actions/setup-environment") | .with.python' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run yq eval '.jobs.lint-format.steps[] | select(.uses == "$/.github/actions/setup-environment" or .uses == "./.github/actions/setup-environment") | .with.galaxy' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run yq eval '.jobs.lint-format.steps[] | select(.uses == "$/.github/actions/setup-environment" or .uses == "./.github/actions/setup-environment") | .with.tflint' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "ci.yml exclusively uses self-repository syntax ($/...) for local actions" {
  run grep -F "uses: ./.github/actions/" "$WORKFLOW"
  [ "$status" -ne 0 ]

  run grep -F "uses: $/.github/actions/setup-environment" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 5 ]
}

@test "actionlint configuration exists and ignores $/ self-repository false positives" {
  [ -f "$REPO_ROOT/.github/actionlint.yaml" ]
  run yq eval '.paths.".github/workflows/**/*.{yml,yaml}".ignore[0]' "$REPO_ROOT/.github/actionlint.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ref is missing" ]] || false
}

@test "setup-environment caches tflint plugins with cache-tflint id and skips init on cache hit" {
  run yq eval '.runs.steps[] | select(.name == "Cache TFLint Plugins") | .id' "$ACTION"
  [ "$status" -eq 0 ]
  [ "$output" = "cache-tflint" ]

  run yq eval '.runs.steps[] | select(.name == "Initialize TFLint") | .if' "$ACTION"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "steps.cache-tflint.outputs.cache-hit != 'true'" ]] || false
}

@test "setup-environment caches ansible galaxy with cache-galaxy id and skips install on cache hit" {
  run yq eval '.runs.steps[] | select(.name == "Cache Ansible Galaxy") | .id' "$ACTION"
  [ "$status" -eq 0 ]
  [ "$output" = "cache-galaxy" ]

  run yq eval '.runs.steps[] | select(.name == "Install Ansible Galaxy requirements") | .if' "$ACTION"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "steps.cache-galaxy.outputs.cache-hit != 'true'" ]] || false
}

@test "setup-environment ansible-galaxy install does not specify --force" {
  run yq eval '.runs.steps[] | select(.name == "Install Ansible Galaxy requirements") | .run' "$ACTION"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "--force" ]] || false
}

@test "codeql, drift-detection, and backup-prune invoke setup-environment with lean defaults" {
  for wf in codeql.yml drift-detection.yml backup-prune.yml; do
    run grep -F "uses: $/.github/actions/setup-environment" "$REPO_ROOT/.github/workflows/$wf"
    [ "$status" -eq 0 ]

    # None of these lean workflows should enable python, galaxy, or tflint
    run yq eval '.. | select(.uses? == "$/.github/actions/setup-environment") | .with.python // "false"' "$REPO_ROOT/.github/workflows/$wf"
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]

    run yq eval '.. | select(.uses? == "$/.github/actions/setup-environment") | .with.galaxy // "false"' "$REPO_ROOT/.github/workflows/$wf"
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]

    run yq eval '.. | select(.uses? == "$/.github/actions/setup-environment") | .with.tflint // "false"' "$REPO_ROOT/.github/workflows/$wf"
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
  done
}

@test "ci.yml paths filter includes .python-version, pyproject.toml, and uv.lock in critical check jobs" {
  run yq eval '.jobs.changes.steps[] | select(.id == "filter") | .with.filters' "$WORKFLOW"
  [ "$status" -eq 0 ]
  local filters="$output"

  # Ensure lint filter checks python version and lock files
  [[ "$filters" =~ ".python-version" ]] || false
  [[ "$filters" =~ "uv.lock" ]] || false
  [[ "$filters" =~ "mise.lock" ]] || false

  # Ensure ansible filter checks python version and dependencies
  run yq eval '.jobs.changes.steps[] | select(.id == "filter") | .with.filters' "$WORKFLOW"
  [ "$status" -eq 0 ]
  local ansible_section
  ansible_section=$(echo "$output" | sed -n '/ansible:/,/molecule:/p')
  [[ "$ansible_section" =~ ".python-version" ]] || false
  [[ "$ansible_section" =~ "pyproject.toml" ]] || false
  [[ "$ansible_section" =~ "uv.lock" ]] || false

  # Ensure molecule filter checks python version and dependencies
  local molecule_section
  molecule_section=$(echo "$output" | sed -n '/molecule:/,$ p')
  [[ "$molecule_section" =~ ".python-version" ]] || false
  [[ "$molecule_section" =~ "pyproject.toml" ]] || false
  [[ "$molecule_section" =~ "uv.lock" ]] || false
}

@test "ci.yml caches molecule apt archives in molecule matrix job" {
  local cache_step
  cache_step=$(yq eval '.jobs.molecule.steps[] | select(.name == "Cache Molecule APT Archives")' "$WORKFLOW")
  [ -n "$cache_step" ]

  run yq eval '.jobs.molecule.steps[] | select(.name == "Cache Molecule APT Archives") | .uses' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "actions/cache@" ]] || false

  run yq eval '.jobs.molecule.steps[] | select(.name == "Cache Molecule APT Archives") | .with.key' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "molecule-apt-\${{ matrix.scenario }}-" ]] || false

  run yq eval '.jobs.molecule.steps[] | select(.name == "Cache Molecule APT Archives") | .with.path' "$WORKFLOW"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "configuration/roles/base_ubuntu_server/.cache/apt/archives"
  echo "$output" | grep -q "configuration/roles/restic_backup/.cache/apt/archives"
  echo "$output" | grep -q "configuration/.cache/apt/oci/archives"
  echo "$output" | grep -q "configuration/.cache/apt/gcp/archives"
  echo "$output" | grep -q "configuration/.cache/apt/homelab/archives"
}

@test "ci.yml includes gcp scenario in molecule matrix and ansible-check syntax check" {
  run yq eval '.jobs.molecule.strategy.matrix.scenario[]' "$WORKFLOW"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^gcp$"

  run grep -F "configuration/playbooks/gcp.yml" "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F "configuration/inventories/fixtures/gcp_state.json" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "ci.yml caches OpenTofu plugins in tofu-validate job" {
  local cache_step
  cache_step=$(yq eval '.jobs.tofu-validate.steps[] | select(.name == "Cache OpenTofu Plugins")' "$WORKFLOW")
  [ -n "$cache_step" ]

  run yq eval '.jobs.tofu-validate.steps[] | select(.name == "Cache OpenTofu Plugins") | .uses' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "actions/cache@" ]] || false

  run yq eval '.jobs.tofu-validate.steps[] | select(.name == "Cache OpenTofu Plugins") | .with.path' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = ".cache/tofu/plugins" ]

  run yq eval '.jobs.tofu-validate.steps[] | select(.name == "Cache OpenTofu Plugins") | .with.key' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "tofu-plugins-" ]] || false
  [[ "$output" =~ "hashFiles('infrastructure/**/.terraform.lock.hcl')" ]]
}

@test "ci.yml shell-bats job executes test:scripts via mise" {
  run yq eval '.jobs.shell-bats.steps[] | select(.name == "Run Bats tests") | .run' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "mise run test:scripts" ]
}

@test "ci.yml cleans up apt locks and fixes permissions for molecule apt cache" {
  local cleanup_step
  cleanup_step=$(yq eval '.jobs.molecule.steps[] | select(.name == "Prepare Molecule APT Cache for Saving")' "$WORKFLOW")
  [ -n "$cleanup_step" ]

  run yq eval '.jobs.molecule.steps[] | select(.name == "Prepare Molecule APT Cache for Saving") | .if' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "always()" ]

  run yq eval '.jobs.molecule.steps[] | select(.name == "Prepare Molecule APT Cache for Saving") | .run' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "name lock" ]] || false
  [[ "$output" =~ "name partial" ]] || false
  [[ "$output" =~ "chown -R" ]] || false
  [[ "$output" =~ "chmod -R" ]]
}

@test "no workflow job uses a floating -latest runner label" {
  run grep -rnE '^[[:space:]]*runs-on:[[:space:]]*[^#]*-latest' "${REPO_ROOT}/.github/workflows/"
  [ "$status" -eq 1 ]
}

@test "every workflow job pins its runner to a versioned ubuntu image" {
  local wf jobs pinned
  for wf in "${REPO_ROOT}"/.github/workflows/*.yml; do
    jobs="$(yq '.jobs | length' "$wf")"
    pinned="$(yq '[.jobs[] | select(.["runs-on"] | test("^ubuntu-[0-9]{2}\\.[0-9]{2}$"))] | length' "$wf")"
    [ "$jobs" -eq "$pinned" ] || {
      echo "unpinned runner in ${wf}" >&2
      false
    }
  done
}

@test "all workflow jobs use one runner image (bumped together, deliberately)" {
  run bash -c "cat '${REPO_ROOT}'/.github/workflows/*.yml | yq -N '.jobs[].runs-on' | sort -u"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
}
@test "PR lefthook run excludes deleted files from the changed-file list" {
  # Deleted paths make file-based hooks (e.g. ansible-lint) fail with load errors.
  run grep -F -- 'git diff --name-only --diff-filter=d -z "origin/${BASE_REF}...HEAD"' "${REPO_ROOT}/.github/workflows/ci.yml"
  [ "$status" -eq 0 ]
}

@test "no workflow consumes the production state passphrase secret" {
  run grep -rn 'TOFU_ENCRYPTION_PASSPHRASE' "${REPO_ROOT}/.github/workflows/"
  [ "$status" -eq 1 ]
}

@test "github module no longer reads a local age keyring or uploads the state passphrase" {
  run grep -rnE 'sops_age_key_file|keys\.txt|TOFU_ENCRYPTION_PASSPHRASE[[:space:]]*=' "${REPO_ROOT}/infrastructure/github/" --include=*.tf
  [ "$status" -eq 1 ]
}

@test "tofu-validate job does not bind to a secret-bearing environment" {
  run yq '.jobs["tofu-validate"].environment // "none"' "${REPO_ROOT}/.github/workflows/ci.yml"
  [ "$output" = "none" ]
}

@test "lint-format job binds the synthetic-only ci environment for the SOPS leak backstop" {
  run yq '.jobs.lint-format.environment // "none"' "$WORKFLOW"
  [ "$output" = "ci" ]
}

@test "lint-format scopes SOPS_AGE_KEY to a dedicated SOPS leak scanner step only (STD-CI-28)" {
  run yq '[.jobs.lint-format.steps[] | select(.env.SOPS_AGE_KEY != null)] | length' "$WORKFLOW"
  [ "$output" = "1" ]

  run yq '.jobs.lint-format.steps[] | select(.env.SOPS_AGE_KEY != null) | .env.SOPS_AGE_KEY' "$WORKFLOW"
  [ "$output" = '${{ secrets.SOPS_AGE_KEY_CI }}' ]

  run yq '.jobs.lint-format.steps[] | select(.env.SOPS_AGE_KEY != null) | .run' "$WORKFLOW"
  [[ "$output" == *"scripts/check-sops-secret-leaks.sh --check-disjointness --all-files"* ]] || false
  [[ "$output" != *"lefthook"* ]]
}

@test "lint-format lefthook backstop excludes only the SOPS hooks that run in their own step" {
  run yq '.jobs.lint-format.steps[] | select(.name == "Run Lefthook Linters") | .env.LEFTHOOK_EXCLUDE' "$WORKFLOW"
  [ "$output" = "sops-secret-leaks,sops-disjointness" ]

  run yq '.jobs.lint-format.env // {} | length' "$WORKFLOW"
  [ "$output" = "0" ]
}

@test "ci.yml triggers on merge_group checks_requested targeting main (STD-CI-01)" {
  run yq '.on.merge_group.types[]' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "checks_requested" ]

  run yq '.on.merge_group.branches[]' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "main" ]
}

@test "changes job checks out full history on merge_group so dorny/paths-filter can diff base_sha" {
  run yq '.jobs.changes.steps[0].with["fetch-depth"]' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "\${{ github.event_name != 'merge_group' && 1 || 0 }}" ]
}

@test "no workflow uses a pseudo-ternary with a falsy true value (cond && 0 || x always yields x)" {
  run grep -rnE '&&[[:space:]]*(0|false|""|'"''"')[[:space:]]*\|\|' "$REPO_ROOT/.github/workflows" "$REPO_ROOT/.github/actions"
  [ "$status" -eq 1 ]
}

@test "all 5 domain jobs treat merge_group as path-filtered alongside pull_request (STD-CI-05, STD-CI-48)" {
  local job cond
  for job in lint-format shell-bats tofu-validate ansible-check molecule; do
    cond="$(yq ".jobs[\"${job}\"].if" "$WORKFLOW")"
    [[ "$cond" == *"github.event_name != 'pull_request'"* ]] || {
      echo "${job} missing pull_request condition" >&2
      false
    }
    [[ "$cond" == *"github.event_name != 'merge_group'"* ]] || {
      echo "${job} missing merge_group condition" >&2
      false
    }
  done
}

@test "lint-format checkout fetches full history on every event so base diffs resolve" {
  run yq '.jobs.lint-format.steps[0].with["fetch-depth"]' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "lint-format passes EVENT_NAME and MERGE_GROUP_BASE_SHA via env and diffs merge_group safely (STD-CI-36)" {
  run yq '.jobs.lint-format.steps[] | select(.name == "Run Lefthook Linters") | .env.EVENT_NAME' "$WORKFLOW"
  [ "$output" = '${{ github.event_name }}' ]

  run yq '.jobs.lint-format.steps[] | select(.name == "Run Lefthook Linters") | .env.MERGE_GROUP_BASE_SHA' "$WORKFLOW"
  [ "$output" = '${{ github.event.merge_group.base_sha }}' ]

  run grep -F -- 'git diff --name-only --diff-filter=d -z "${MERGE_GROUP_BASE_SHA}...HEAD"' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "ci.yml cancels in-progress runs only for pull_request, never merge_group (STD-CI-44)" {
  run yq '.concurrency["cancel-in-progress"]' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "\${{ github.event_name == 'pull_request' }}" ]
}
