#!/usr/bin/env bats
# Tests for .github/renovate.json5 syntax, preset integrity, and config validation

load 'helpers/test_helper'

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test ".github/renovate.json5 exists and is readable" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  [ -f "$config" ]
  [ -r "$config" ]
}

@test "all presets in extends array contain a colon namespace separator" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  local presets
  presets=$(sed -n '/extends: *\[/,/\]/p' "$config" | grep -o '"[^"]*"' | tr -d '"')

  [ -n "$presets" ]
  while IFS= read -r preset; do
    [[ "$preset" =~ : ]] || {
      echo "Preset '$preset' is missing a colon namespace prefix"
      return 1
    }
  done <<< "$presets"
}

@test "pinAllExceptPeerDependencies preset is correctly prefixed with colon" {
  local config="${REPO_ROOT}/.github/renovate.json5"

  # Must contain :pinAllExceptPeerDependencies
  run grep -E '":pinAllExceptPeerDependencies"' "$config"
  [ "$status" -eq 0 ]

  # Must NOT contain bare "pinAllExceptPeerDependencies" without leading colon
  while IFS= read -r line; do
    if [[ "$line" =~ \"pinAllExceptPeerDependencies\" ]] && [[ ! "$line" =~ \":pinAllExceptPeerDependencies\" ]]; then
      echo "Found bare pinAllExceptPeerDependencies: $line"
      return 1
    fi
  done < "$config"
}

@test "detects and rejects bare unnamespaced presets in extends" {
  local test_fixture="${BATS_TMPDIR}/invalid-renovate.json5"
  cat <<'EOF' > "$test_fixture"
{
  extends: [
    "config:best-practices",
    "pinAllExceptPeerDependencies",
  ]
}
EOF
  local bare_count=0
  local presets
  presets=$(sed -n '/extends: *\[/,/\]/p' "$test_fixture" | grep -o '"[^"]*"' | tr -d '"')
  while IFS= read -r preset; do
    if [[ ! "$preset" =~ : ]]; then
      bare_count=$((bare_count + 1))
    fi
  done <<< "$presets"

  [ "$bare_count" -eq 1 ]
}

@test "renovate-config-validator validates .github/renovate.json5" {
  run npx --prefer-offline --yes --package renovate renovate-config-validator --strict "${REPO_ROOT}/.github/renovate.json5"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Config validated successfully" ]]
}

@test "renovate presets in .github/renovate.json5 resolve successfully without errors" {
  run node -e '
const fs = require("fs");
const path = require("path");

let presets;
try {
  presets = require("renovate/dist/config/presets/index.js");
} catch {
  const npxDir = path.join(process.env.HOME, ".npm/_npx");
  if (fs.existsSync(npxDir)) {
    const entries = fs.readdirSync(npxDir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isDirectory()) {
        const candidate = path.join(npxDir, entry.name, "node_modules/renovate/dist/config/presets/index.js");
        if (fs.existsSync(candidate)) {
          presets = require(candidate);
          break;
        }
      }
    }
  }
}

if (!presets) {
  console.log("Renovate module not found; skipping");
  process.exit(0);
}

const configPath = process.argv[1];
const content = fs.readFileSync(configPath, "utf8");
const extendsMatch = content.match(/extends:\s*\[([\s\S]*?)\]/);
if (!extendsMatch) {
  console.error("No extends array found");
  process.exit(1);
}

const presetNames = extendsMatch[1]
  .split("\n")
  .map(line => line.trim())
  .filter(line => line.startsWith("\"") || line.startsWith("\x27"))
  .map(line => line.replace(/^["\x27]|["\x27],?$/g, ""));

(async () => {
  for (const preset of presetNames) {
    try {
      await presets.resolveConfigPresets({ extends: [preset] });
    } catch (err) {
      console.error("Failed to resolve preset " + preset + ": " + (err.message || err));
      process.exit(1);
    }
  }
  console.log("All " + presetNames.length + " presets resolved successfully");
})();
' "${REPO_ROOT}/.github/renovate.json5"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "resolved successfully" ]] || [[ "$output" =~ "skipping" ]]
}

@test "renovate preset resolver rejects bare pinAllExceptPeerDependencies preset" {
  run node -e '
const fs = require("fs");
const path = require("path");

let presets;
try {
  presets = require("renovate/dist/config/presets/index.js");
} catch {
  const npxDir = path.join(process.env.HOME, ".npm/_npx");
  if (fs.existsSync(npxDir)) {
    const entries = fs.readdirSync(npxDir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isDirectory()) {
        const candidate = path.join(npxDir, entry.name, "node_modules/renovate/dist/config/presets/index.js");
        if (fs.existsSync(candidate)) {
          presets = require(candidate);
          break;
        }
      }
    }
  }
}

if (!presets) {
  console.log("Renovate module not found; skipping negative check");
  process.exit(0);
}

(async () => {
  try {
    await presets.resolveConfigPresets({ extends: ["pinAllExceptPeerDependencies"] });
    console.error("Expected resolution failure but succeeded");
    process.exit(1);
  } catch (err) {
    if (String(err.validationError || err.message).includes("Cannot find preset")) {
      console.log("Correctly rejected bare preset:", err.validationError || err.message);
      process.exit(0);
    }
    console.error("Unexpected error:", err);
    process.exit(1);
  }
})();
'

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Correctly rejected bare preset" ]] || [[ "$output" =~ "skipping" ]]
}

@test ".github/renovate.json5 does not configure postUpgradeTasks" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  run grep -E "postUpgradeTasks" "$config"
  [ "$status" -ne 0 ]
}

@test "mise.toml defines skills:update task using npx skills update" {
  local config="${REPO_ROOT}/mise.toml"
  [ -f "$config" ]
  run grep -E '\[tasks\."skills:update"\]' "$config"
  [ "$status" -eq 0 ]

  run grep -E 'npx skills update' "$config"
  [ "$status" -eq 0 ]
}

@test ".github/renovate.json5 separates 0.x and stable versions into distinct groups across all managers" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  run node -e '
const fs = require("fs");
const content = fs.readFileSync(process.argv[1], "utf8");
const config = eval("(" + content + ")");

const expectedManagers = [
  { manager: "terraform", slug: "terraform-deps" },
  { manager: "ansible", slug: "ansible-deps" },
  { manager: "github-actions", slug: "github-actions-deps" },
  { manager: "mise", slug: "mise-deps" },
  { manager: "pep621", slug: "python-deps" },
];

for (const { manager, slug } of expectedManagers) {
  const stableRule = config.packageRules.find(r =>
    Array.isArray(r.matchManagers) &&
    r.matchManagers.includes(manager) &&
    r.matchCurrentVersion === "!/^0\\./" &&
    r.groupSlug === slug
  );
  if (!stableRule) {
    console.error("Missing stable rule for manager: " + manager + " with slug: " + slug);
    process.exit(1);
  }

  const initialDevRule = config.packageRules.find(r =>
    Array.isArray(r.matchManagers) &&
    r.matchManagers.includes(manager) &&
    r.matchCurrentVersion === "/^0\\./" &&
    r.groupSlug === slug + "-0x"
  );
  if (!initialDevRule) {
    console.error("Missing 0.x initial development rule for manager: " + manager + " with slug: " + slug + "-0x");
    process.exit(1);
  }

  if (initialDevRule.automerge !== false) {
    console.error("0.x rule for manager: " + manager + " must explicitly set automerge: false");
    process.exit(1);
  }
}

console.log("All managers correctly separate 0.x and stable versions into distinct groups");
' "$config"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "All managers correctly separate" ]]
}

@test ".github/renovate.json5 ensures stable package groups allow automerge and 0.x groups disable automerge" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  run node -e '
const fs = require("fs");
const content = fs.readFileSync(process.argv[1], "utf8");
const config = eval("(" + content + ")");

// Verify all 0x group rules explicitly disable automerge
const zeroXRules = config.packageRules.filter(r => r.groupSlug && r.groupSlug.endsWith("-0x"));
if (zeroXRules.length === 0) {
  console.error("No 0.x group rules found");
  process.exit(1);
}

for (const rule of zeroXRules) {
  if (rule.automerge !== false) {
    console.error("Rule " + rule.groupSlug + " does not have automerge: false");
    process.exit(1);
  }
  if (rule.matchCurrentVersion !== "/^0\\./") {
    console.error("Rule " + rule.groupSlug + " must match /^0\\./");
    process.exit(1);
  }
}

// Verify global automerge rule specifically excludes 0.x
const automergeRule = config.packageRules.find(r => r.automerge === true && r.platformAutomerge === true);
if (!automergeRule) {
  console.error("Global platform automerge rule not found");
  process.exit(1);
}
if (automergeRule.matchCurrentVersion !== "!/^0\\./") {
  console.error("Global automerge rule must restrict matchCurrentVersion to !/^0\\./");
  process.exit(1);
}

console.log("Automerge policy correctly isolates 0.x from stable groups");
' "$config"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Automerge policy correctly isolates" ]]
}

@test ".github/renovate.json5 configures ignorePaths containing **/.mise/locks/**" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  run node -e '
const fs = require("fs");
const content = fs.readFileSync(process.argv[1], "utf8");
const config = eval("(" + content + ")");

if (!Array.isArray(config.ignorePaths)) {
  console.error("ignorePaths is not an array");
  process.exit(1);
}

if (!config.ignorePaths.includes("**/.mise/locks/**")) {
  console.error("ignorePaths does not include **/.mise/locks/**");
  process.exit(1);
}

console.log("ignorePaths correctly includes **/.mise/locks/**");
' "$config"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "ignorePaths correctly includes **/.mise/locks/**" ]]
}

@test ".github/renovate.json5 configures customManager regex manager for jdx/mise" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  local mise_toml="${REPO_ROOT}/mise.toml"
  local action_yml="${REPO_ROOT}/.github/actions/setup-environment/action.yml"

  run node -e '
const fs = require("fs");
const content = fs.readFileSync(process.argv[1], "utf8");
const config = eval("(" + content + ")");

const miseManager = config.customManagers.find(m =>
  m.customType === "regex" &&
  Array.isArray(m.managerFilePatterns) &&
  m.managerFilePatterns.some(p => new RegExp(p).test("mise.toml")) &&
  m.managerFilePatterns.some(p => new RegExp(p).test(".github/actions/setup-environment/action.yml"))
);

if (!miseManager) {
  console.error("Custom manager for mise toolchain pins not found in customManagers");
  process.exit(1);
}

const matchPattern = new RegExp(miseManager.matchStrings[0]);
const miseContent = fs.readFileSync(process.argv[2], "utf8");
const actionContent = fs.readFileSync(process.argv[3], "utf8");

const matchMise = miseContent.match(matchPattern);
if (!matchMise || matchMise.groups.depName !== "jdx/mise" || !matchMise.groups.currentValue) {
  console.error("Custom manager regex failed to match mise.toml: " + JSON.stringify(matchMise ? matchMise.groups : null));
  process.exit(1);
}

const matchAction = actionContent.match(matchPattern);
if (!matchAction || matchAction.groups.depName !== "jdx/mise" || !matchAction.groups.currentValue) {
  console.error("Custom manager regex failed to match action.yml: " + JSON.stringify(matchAction ? matchAction.groups : null));
  process.exit(1);
}

if (matchMise.groups.currentValue !== matchAction.groups.currentValue) {
  console.error("Version mismatch between mise.toml (" + matchMise.groups.currentValue + ") and action.yml (" + matchAction.groups.currentValue + ")");
  process.exit(1);
}

console.log("Custom manager regex successfully matches and extracts synchronized jdx/mise version: " + matchMise.groups.currentValue);
' "$config" "$mise_toml" "$action_yml"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Custom manager regex successfully matches" ]]
}

@test ".github/renovate.json5 configures packageRule grouping jdx/mise under mise-cli" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  run node -e '
const fs = require("fs");
const content = fs.readFileSync(process.argv[1], "utf8");
const config = eval("(" + content + ")");

const miseRule = config.packageRules.find(r =>
  Array.isArray(r.matchPackageNames) &&
  r.matchPackageNames.includes("jdx/mise")
);

if (!miseRule) {
  console.error("Package rule for jdx/mise not found in packageRules");
  process.exit(1);
}

if (miseRule.groupSlug !== "mise-cli") {
  console.error("Expected groupSlug to be mise-cli, got: " + miseRule.groupSlug);
  process.exit(1);
}

if (miseRule.semanticCommitScope !== "toolchain") {
  console.error("Expected semanticCommitScope to be toolchain, got: " + miseRule.semanticCommitScope);
  process.exit(1);
}

if (miseRule.automerge !== false) {
  console.error("Expected automerge to be false for jdx/mise, got: " + miseRule.automerge);
  process.exit(1);
}

console.log("Package rule for jdx/mise correctly configured with groupSlug mise-cli and automerge false");
' "$config"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Package rule for jdx/mise correctly configured" ]]
}

@test ".github/renovate.json5 does not configure .python-version in ignorePaths" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  run node -e '
const fs = require("fs");
const content = fs.readFileSync(process.argv[1], "utf8");
const config = eval("(" + content + ")");

if (Array.isArray(config.ignorePaths) && config.ignorePaths.includes(".python-version")) {
  console.error("ignorePaths still includes obsolete .python-version");
  process.exit(1);
}

console.log("ignorePaths does not include .python-version");
' "$config"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "ignorePaths does not include .python-version" ]]
}

@test ".github/renovate.json5 configures rangeStrategy bump for PEP 621 python" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  run node -e '
const fs = require("fs");
const content = fs.readFileSync(process.argv[1], "utf8");
const config = eval("(" + content + ")");

const rule = config.packageRules.find(r =>
  Array.isArray(r.matchManagers) &&
  r.matchManagers.includes("pep621") &&
  Array.isArray(r.matchPackageNames) &&
  r.matchPackageNames.includes("python") &&
  r.rangeStrategy === "bump"
);

if (!rule) {
  console.error("Package rule with rangeStrategy: bump for pep621 python not found");
  process.exit(1);
}

console.log("rangeStrategy bump correctly configured for pep621 python");
' "$config"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "rangeStrategy bump correctly configured for pep621 python" ]]
}

@test ".github/renovate.json5 groups python runtime updates across mise and pep621" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  run node -e '
const fs = require("fs");
const content = fs.readFileSync(process.argv[1], "utf8");
const config = eval("(" + content + ")");

const runtimeGroupRule = config.packageRules.find(r =>
  Array.isArray(r.matchManagers) &&
  r.matchManagers.includes("mise") &&
  r.matchManagers.includes("pep621") &&
  Array.isArray(r.matchPackageNames) &&
  r.matchPackageNames.includes("python") &&
  r.groupSlug === "python-runtime"
);

if (!runtimeGroupRule) {
  console.error("Unified python runtime group rule not found");
  process.exit(1);
}

if (runtimeGroupRule.automerge !== false) {
  console.error("Expected automerge: false for python runtime group");
  process.exit(1);
}

console.log("Unified python runtime group correctly configured with automerge false");
' "$config"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Unified python runtime group correctly configured" ]]
}

@test ".github/renovate.json5 explicitly disables pyenv and nodenv managers" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  run node -e '
const fs = require("fs");
const content = fs.readFileSync(process.argv[1], "utf8");
const config = eval("(" + content + ")");

if (!config.pyenv || config.pyenv.enabled !== false) {
  console.error("pyenv manager is not disabled: " + JSON.stringify(config.pyenv));
  process.exit(1);
}

if (!config.nodenv || config.nodenv.enabled !== false) {
  console.error("nodenv manager is not disabled: " + JSON.stringify(config.nodenv));
  process.exit(1);
}

console.log("pyenv and nodenv managers are explicitly disabled");
' "$config"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "pyenv and nodenv managers are explicitly disabled" ]]
}

@test ".github/renovate.json5 disables automerge for mise language runtimes" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  run node -e '
const fs = require("fs");
const content = fs.readFileSync(process.argv[1], "utf8");
const config = eval("(" + content + ")");

const runtimeRule = config.packageRules.find(r =>
  Array.isArray(r.matchManagers) &&
  r.matchManagers.includes("mise") &&
  Array.isArray(r.matchPackageNames) &&
  ["python", "node", "go"].every(pkg => r.matchPackageNames.includes(pkg))
);

if (!runtimeRule) {
  console.error("Package rule for mise language runtimes not found");
  process.exit(1);
}

if (runtimeRule.automerge !== false) {
  console.error("Expected automerge: false for language runtimes, got: " + runtimeRule.automerge);
  process.exit(1);
}

console.log("Mise language runtimes rule correctly configured with automerge false");
' "$config"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Mise language runtimes rule correctly configured" ]]
}



@test ".github/renovate.json5 sets a global minimumReleaseAge of at least 3 days" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  run node -e '
const config = eval("(" + require("fs").readFileSync(process.argv[1], "utf8") + ")");
const m = /^(\d+) days?$/.exec(config.minimumReleaseAge || "");
if (!m || Number(m[1]) < 3) { console.error("minimumReleaseAge must be >= 3 days"); process.exit(1); }
console.log("cooldown ok");
' "$config"
  [ "$status" -eq 0 ]
}

@test ".github/renovate.json5 places every never-automerge gate after the automerge rule" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  run node -e '
const config = eval("(" + require("fs").readFileSync(process.argv[1], "utf8") + ")");
const rules = config.packageRules;
const automergeIdx = rules.findIndex(r => r.automerge === true && r.platformAutomerge === true);
if (automergeIdx < 0) { console.error("automerge rule missing"); process.exit(1); }
const has = (r, k, v) => Array.isArray(r[k]) && r[k].includes(v);
const gates = {
  "runtime (mise)": r => r.automerge === false && has(r, "matchManagers", "mise") && has(r, "matchPackageNames", "python"),
  "runtime (pep621)": r => r.automerge === false && has(r, "matchManagers", "pep621") && has(r, "matchPackageNames", "python"),
  "mise cli": r => r.automerge === false && has(r, "matchPackageNames", "jdx/mise"),
  "agent skills": r => r.automerge === false && has(r, "matchFileNames", "skills-lock.json"),
  "security boundary": r => r.automerge === false && has(r, "matchFileNames", ".sops.yaml"),
  "major": r => r.automerge === false && has(r, "matchUpdateTypes", "major"),
};
for (const [name, pred] of Object.entries(gates)) {
  const last = rules.map((r, i) => pred(r) ? i : -1).filter(i => i >= 0).pop();
  if (last === undefined || last < automergeIdx) { console.error("gate not after automerge rule: " + name); process.exit(1); }
}
console.log("gates ordered after automerge");
' "$config"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gates ordered after automerge"* ]]
}

@test ".github/renovate.json5 disables the terraform required_version depType" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  run node -e '
const config = eval("(" + require("fs").readFileSync(process.argv[1], "utf8") + ")");
const ok = config.packageRules.some(r => r.enabled === false &&
  (r.matchManagers || []).includes("terraform") && (r.matchDepTypes || []).includes("required_version"));
if (!ok) { console.error("required_version not disabled"); process.exit(1); }
console.log("required_version disabled");
' "$config"
  [ "$status" -eq 0 ]
}

@test ".github/renovate.json5 sets strict internal checks and never automerges security updates" {
  local config="${REPO_ROOT}/.github/renovate.json5"
  run node -e '
const config = eval("(" + require("fs").readFileSync(process.argv[1], "utf8") + ")");
if (config.internalChecksFilter !== "strict") { console.error("internalChecksFilter must be strict"); process.exit(1); }
const v = config.vulnerabilityAlerts || {};
if (v.automerge !== false) { console.error("vulnerabilityAlerts.automerge must be false"); process.exit(1); }
if (v.minimumReleaseAge !== undefined && v.minimumReleaseAge !== null) { console.error("security updates must bypass the age gate"); process.exit(1); }
console.log("security gates ok");
' "$config"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security gates ok"* ]] || false
}
