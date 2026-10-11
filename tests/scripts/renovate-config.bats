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
  run npx --prefer-offline --yes --package renovate renovate-config-validator "${REPO_ROOT}/.github/renovate.json5"
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

