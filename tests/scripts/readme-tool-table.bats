#!/usr/bin/env bats
# Verifies that the Global Toolset table in README.md matches mise.toml and pyproject.toml (R2-GOV-06)

load 'helpers/test_helper'

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  README="$REPO_ROOT/README.md"
  MISE_TOML="$REPO_ROOT/mise.toml"
  PYPROJECT="$REPO_ROOT/pyproject.toml"
}

@test "README.md Global Toolset table matches mise.toml and pyproject.toml versions" {
  python3 - "$README" "$MISE_TOML" "$PYPROJECT" <<'PY'
import re
import sys
import tomllib
from pathlib import Path

readme = Path(sys.argv[1]).read_text()
mise = tomllib.loads(Path(sys.argv[2]).read_text())["tools"]
pyproject = Path(sys.argv[3]).read_text()

# Map README tool display names to mise.toml keys
mise_key_map = {
    "OpenTofu": "opentofu",
    "TFLint": "tflint",
    "Terraform-Docs": "terraform-docs",
    "SOPS": "sops",
    "Age": "age",
    "Restic": "restic",
    "Lefthook": "lefthook",
    "Python": "python",
    "uv": "aqua:astral-sh/uv",
    "ShellCheck": "shellcheck",
    "Shfmt": "shfmt",
    "Bats": "bats",
    "Rush": "aqua:shenwei356/rush",
    "Trivy": "trivy",
    "TruffleHog": "trufflehog",
    "Actionlint": "actionlint",
    "Act": "act",
    "GitHub CLI (`gh`)": "gh",
    "Oxlint": "oxlint",
    "Oxfmt": "oxfmt",
    "Yq": "yq",
    "Node": "node",
}

pyproject_key_map = {
    "Ansible-Core": "ansible-core",
    "Ansible-Lint": "ansible-lint",
    "Molecule": "molecule",
    "Ruff": "ruff",
}

# Extract Global Toolset table rows
in_section = False
rows = []
for line in readme.splitlines():
    if line.startswith("## 🛠️ Global Toolset"):
        in_section = True
        continue
    if in_section and line.startswith("## "):
        break
    if in_section and line.startswith("| **"):
        parts = [p.strip() for p in line.strip("|").split("|")]
        if len(parts) >= 3:
            tool = re.sub(r"^\*\*|\*\*$", "", parts[0])
            version = parts[1]
            source = parts[2].strip("`")
            rows.append((tool, version, source))

assert rows, "No rows found in README.md Global Toolset table"

seen_mise = set()
for tool, version_cell, source in rows:
    if source == "mise.toml":
        assert tool in mise_key_map, f"Unmapped mise.toml tool in README: {tool}"
        key = mise_key_map[tool]
        seen_mise.add(key)
        assert key in mise, f"Tool {tool} ({key}) listed in README as mise.toml is missing from mise.toml"
        expected = f"`{mise[key]}`"
        assert version_cell == expected, f"Mismatch for {tool}: README has {version_cell}, mise.toml has {expected}"
    elif source == "pyproject.toml":
        assert tool in pyproject_key_map, f"Unmapped pyproject.toml tool in README: {tool}"
        pkg = pyproject_key_map[tool]
        m = re.search(rf'"{re.escape(pkg)}==([^"]+)"', pyproject)
        assert m, f"Package {pkg} not pinned in pyproject.toml"
        pkg_ver = m.group(1)
        assert f"`{pkg_ver}`" in version_cell or version_cell.startswith(f"`{pkg_ver.split('.')[0]}`"), (
            f"Mismatch for {tool}: README has {version_cell}, pyproject.toml has {pkg_ver}"
        )

# Ensure every tool in mise.toml is documented in README.md
missing = set(mise.keys()) - seen_mise
assert not missing, f"mise.toml tools missing from README.md table: {missing}"
PY
}

@test "README.md documents all 6 Molecule scenarios and no longer references removed apps/ or Go" {
  run grep -F "6 automated Ubuntu 26.04 test scenarios" "$README"
  [ "$status" -eq 0 ]

  run grep -F "docker_compose_service" "$README"
  [ "$status" -eq 0 ]

  run grep -F "| **Go**" "$README"
  [ "$status" -ne 0 ]

  run grep -F "├── apps/" "$README"
  [ "$status" -ne 0 ]
}
