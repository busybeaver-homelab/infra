#!/usr/bin/env bash
# =============================================================================
# Verify .agents/skills/ integrity against skills-lock.json (R2-GOV-04)
# =============================================================================
# Enforces that:
#   1. skills-lock.json is valid JSON with version == 1.
#   2. Every skill entry has a pinned 40-hex-character sourceRef commit SHA
#      and a 64-hex-character computedHash.
#   3. Every directory under .agents/skills/<name> corresponds 1:1 with
#      skills-lock.json (no unlisted or missing skill directories).
#   4. Each skill directory's SHA-256 tree digest (matching the skills CLI
#      computeSkillFolderHash algorithm) matches computedHash.
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="${SKILLS_LOCK_FILE:-${REPO_ROOT}/skills-lock.json}"
SKILLS_DIR="${SKILLS_DIR:-${REPO_ROOT}/.agents/skills}"

if [ ! -f "$LOCK_FILE" ]; then
  echo "ERROR: skills-lock.json not found at ${LOCK_FILE}" >&2
  exit 1
fi

if [ ! -d "$SKILLS_DIR" ]; then
  echo "ERROR: skills directory not found at ${SKILLS_DIR}" >&2
  exit 1
fi

node - "$LOCK_FILE" "$SKILLS_DIR" <<'NODE_EOF'
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const [lockFile, skillsDir] = process.argv.slice(2);

let lock;
try {
  lock = JSON.parse(fs.readFileSync(lockFile, "utf8"));
} catch (err) {
  console.error(`ERROR: Failed to parse ${lockFile}: ${err.message}`);
  process.exit(1);
}

if (!lock || typeof lock !== "object" || lock.version !== 1 || !lock.skills || typeof lock.skills !== "object") {
  console.error(`ERROR: ${lockFile} must have version: 1 and a skills object.`);
  process.exit(1);
}

function collectFiles(rootDir, currentDir = rootDir, results = []) {
  const entries = fs.readdirSync(currentDir, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.name === ".git" || entry.name === "node_modules") continue;
    const fullPath = path.join(currentDir, entry.name);
    if (entry.isDirectory()) {
      collectFiles(rootDir, fullPath, results);
    } else if (entry.isFile()) {
      const relativePath = path.relative(rootDir, fullPath).split(path.sep).join("/");
      const content = fs.readFileSync(fullPath);
      results.push({ relativePath, content });
    }
  }
  return results;
}

function computeSkillFolderHash(skillDir) {
  const files = collectFiles(skillDir);
  files.sort((a, b) => a.relativePath.localeCompare(b.relativePath));
  const hash = crypto.createHash("sha256");
  for (const file of files) {
    hash.update(file.relativePath);
    hash.update(file.content);
  }
  return hash.digest("hex");
}

const lockSkills = Object.keys(lock.skills).sort();
const diskSkills = fs
  .readdirSync(skillsDir, { withFileTypes: true })
  .filter((d) => d.isDirectory() && !d.name.startsWith("."))
  .map((d) => d.name)
  .sort();

let failed = false;

for (const diskSkill of diskSkills) {
  if (!Object.prototype.hasOwnProperty.call(lock.skills, diskSkill)) {
    console.error(`ERROR: Unlisted skill directory in .agents/skills: ${diskSkill}`);
    failed = true;
  }
}

for (const skillName of lockSkills) {
  const entry = lock.skills[skillName];
  const skillDir = path.join(skillsDir, skillName);

  if (!fs.existsSync(skillDir) || !fs.statSync(skillDir).isDirectory()) {
    console.error(`ERROR: Skill '${skillName}' in skills-lock.json is missing directory ${skillDir}`);
    failed = true;
    continue;
  }

  if (!entry.sourceRef || !/^[0-9a-f]{40}$/.test(entry.sourceRef)) {
    console.error(
      `ERROR: Skill '${skillName}' in skills-lock.json is missing a valid 40-character hex sourceRef commit SHA (got: ${JSON.stringify(entry.sourceRef)})`
    );
    failed = true;
  }

  if (!entry.computedHash || !/^[0-9a-f]{64}$/.test(entry.computedHash)) {
    console.error(
      `ERROR: Skill '${skillName}' in skills-lock.json is missing a valid 64-character hex computedHash`
    );
    failed = true;
    continue;
  }

  const actualHash = computeSkillFolderHash(skillDir);
  if (actualHash !== entry.computedHash) {
    console.error(
      `ERROR: Skill '${skillName}' folder hash mismatch:\n  expected (skills-lock.json): ${entry.computedHash}\n  actual (.agents/skills/${skillName}): ${actualHash}`
    );
    failed = true;
  }
}

if (failed) {
  process.exit(1);
}
NODE_EOF
