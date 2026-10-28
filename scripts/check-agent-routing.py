#!/usr/bin/env python3
"""Validate the project-scoped, offline agent routing policy."""

import argparse
import json
import tomllib
from datetime import date
from pathlib import Path

import yaml

ROLES = ("coordinator", "implementer", "simple", "reviewer")
MODELS = {
    "codex": ("gpt-6.1-sol", "gpt-6.1-terra", "gpt-6-luna", "gpt-6.1-sol"),
    "claude": ("opus", "sonnet", "haiku", "opus"),
    "antigravity": ("pro", "flash", "flash", "pro"),
}
RESOLVED = {
    "codex": tuple((m,) for m in MODELS["codex"]),
    "claude": (
        ("claude-opus-5-5",),
        ("claude-sonnet-5-5",),
        ("claude-haiku-5-5",),
        ("claude-opus-5-5",),
    ),
    "antigravity": (
        ("gemini-4-argon", "gemini-3.1-pro-preview"),
        ("gemini-3.8-flash",),
        ("gemini-3.8-flash",),
        ("gemini-4-argon", "gemini-3.1-pro-preview"),
    ),
}
SOURCES = {
    "codex": ["https://learn.chatgpt.com/docs/agent-configuration/subagents"],
    "claude": ["https://code.claude.com/docs/en/model-config"],
    "antigravity": [
        "https://antigravity.google/docs/models/",
        "https://antigravity.google/docs/subagents",
    ],
}


CLAUDE_READ = {"Read", "Grep", "Glob"}
CLAUDE_TOOLS = CLAUDE_READ | {"Edit", "Write", "Bash"}
ANTIGRAVITY_READ = {
    "view_file",
    "view_file_outline",
    "view_code_item",
    "grep_search",
    "find_by_name",
    "list_dir",
}
ANTIGRAVITY_TOOLS = ANTIGRAVITY_READ | {"replace_file_content", "run_command"}


def unique_pairs(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate key")
        result[key] = value
    return result


class UniqueSafeLoader(yaml.SafeLoader):
    """Safe loader for the restricted, alias-free frontmatter schema."""


def unique_mapping(loader: UniqueSafeLoader, node: yaml.MappingNode) -> dict:
    result = {}
    for key_node, value_node in node.value:
        if key_node.tag == "tag:yaml.org,2002:merge":
            raise ValueError("merge")
        key = loader.construct_object(key_node)
        if key in result:
            raise ValueError("duplicate key")
        result[key] = loader.construct_object(value_node)
    return result


UniqueSafeLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping
)


def read_json(path: Path) -> object:
    return json.loads(path.read_text(), object_pairs_hook=unique_pairs)


def review_due(reviewed_on: date, as_of: date, review_after_days: int) -> bool:
    return (as_of - reviewed_on).days >= review_after_days


def frontmatter(path: Path) -> tuple[dict, str]:
    text = path.read_text(encoding="utf-8")
    parts = text.split("---", 2)
    if len(parts) != 3 or parts[0].strip():
        raise ValueError("frontmatter")
    if any(
        isinstance(token, (yaml.tokens.AliasToken, yaml.tokens.AnchorToken))
        for token in yaml.scan(parts[1])
    ):
        raise ValueError("aliases")
    value = yaml.load(parts[1], Loader=UniqueSafeLoader)
    if not isinstance(value, dict):
        raise ValueError("frontmatter")
    return value, parts[2]


def validate_repository(root: Path) -> list[str]:
    diagnostics = set()

    def check(condition: bool, code: str) -> None:
        if not condition:
            diagnostics.add(code)

    def nonempty(value: object) -> bool:
        return isinstance(value, str) and bool(value.strip())

    def permissions(value: object) -> None:
        if isinstance(value, dict):
            for key, item in value.items():
                lower = str(key).lower().replace("_", "")
                if lower in {"permissionmode", "defaultmode"} or "bypass" in lower:
                    diagnostics.add("unsafe_permissions")
                if lower in {
                    "sandboxmode",
                    "sandbox",
                    "provider",
                    "forcedsubagentmodel",
                    "subagentmodel",
                    "modelprovider",
                    "claudecodesubagentmodel",
                    "claudecodesubagentmodelforce",
                }:
                    diagnostics.add("unsafe_settings")
                permissions(item)
        elif isinstance(value, list):
            for item in value:
                permissions(item)

    try:
        manifest = read_json(root / ".agent-models.json")
        check(
            manifest.get("schema_version") == 1
            and manifest.get("review_after_days") == 30,
            "invalid_manifest",
        )
        date.fromisoformat(manifest["reviewed_on"])
        providers = manifest["providers"]
        check(set(providers) == set(MODELS), "invalid_manifest")
        for provider, expected in MODELS.items():
            roles = providers[provider]["roles"]
            check(set(roles) == set(ROLES), "invalid_manifest")
            for i, role in enumerate(ROLES):
                entry = roles[role]
                check(entry.get("native_model") == expected[i], "invalid_manifest")
                check(
                    entry.get("approved_resolved_models")
                    == list(RESOLVED[provider][i]),
                    "invalid_manifest",
                )
                check(entry.get("source_urls") == SOURCES[provider], "invalid_manifest")
                effort = "high" if i in (0, 3) else "medium"
                check(
                    entry.get("reasoning_effort")
                    == (effort if provider == "codex" else None),
                    "invalid_manifest",
                )
        config = tomllib.loads((root / ".codex/config.toml").read_text())
        permissions(config)
        check(
            config.get("model") == MODELS["codex"][0]
            and config.get("model_reasoning_effort") == "high",
            "model_mismatch",
        )
        agents = config.get("agents", {})
        check(
            agents.get("enabled") is True
            and agents.get("max_concurrent_threads_per_session") == 1,
            "unsafe_settings",
        )
        check(
            agents.get("default_subagent_model") == MODELS["codex"][1]
            and agents.get("default_subagent_reasoning_effort") == "medium",
            "model_mismatch",
        )
        settings = read_json(root / ".claude/settings.json")
        permissions(settings)
        check(settings.get("model") == MODELS["claude"][0], "model_mismatch")
        check("@AGENTS.md" in (root / "CLAUDE.md").read_text(), "policy_import_missing")
        rule, body = frontmatter(root / ".agents/rules/model-routing.md")
        check(
            rule.get("trigger") == "always_on" and "AGENTS.md" in body,
            "policy_import_missing",
        )
        for provider in MODELS:
            directory = root / (
                ".codex/agents"
                if provider == "codex"
                else ".claude/agents"
                if provider == "claude"
                else ".agents/agents"
            )
            extension = "toml" if provider == "codex" else "md"
            expected_roles = ROLES if provider == "antigravity" else ROLES[1:]
            check(
                {p.name for p in directory.glob(f"routing-*.{extension}")}
                == {f"routing-{r}.{extension}" for r in expected_roles},
                "invalid_roles",
            )
            for role in expected_roles:
                i = ROLES.index(role)
                path = directory / f"routing-{role}.{extension}"
                data = (
                    tomllib.loads(path.read_text())
                    if provider == "codex"
                    else frontmatter(path)[0]
                )
                permissions(data)
                check(
                    data.get("name") == f"routing-{role}"
                    and nonempty(data.get("description")),
                    "invalid_roles",
                )
                check(data.get("model") == MODELS[provider][i], "model_mismatch")
                if provider == "codex":
                    check(
                        set(data)
                        <= {
                            "name",
                            "description",
                            "developer_instructions",
                            "model",
                            "model_reasoning_effort",
                        },
                        "unsafe_settings",
                    )
                    check(nonempty(data.get("developer_instructions")), "invalid_roles")
                    check(
                        data.get("model_reasoning_effort")
                        == ("high" if role == "reviewer" else "medium"),
                        "model_mismatch",
                    )
                else:
                    tools = data.get("tools")
                    names = (
                        [name.strip() for name in tools.split(",")]
                        if isinstance(tools, str)
                        else tools
                    )
                    allowed = (
                        CLAUDE_TOOLS if provider == "claude" else ANTIGRAVITY_TOOLS
                    )
                    read_only = (
                        CLAUDE_READ if provider == "claude" else ANTIGRAVITY_READ
                    )
                    valid = (
                        isinstance(names, list)
                        and bool(names)
                        and all(
                            isinstance(name, str) and name in allowed for name in names
                        )
                    )
                    check(valid, "invalid_roles")
                    if role == "reviewer" and valid:
                        check(set(names) <= read_only, "unsafe_permissions")
                    allowed_fields = {"name", "description", "model", "tools"}
                    if provider == "antigravity":
                        allowed_fields |= {
                            "mainAgent",
                            "subagent",
                            "commandExecutionPolicy",
                        }
                    check(set(data) <= allowed_fields, "unsafe_settings")
                if provider == "antigravity":
                    check(
                        data.get("mainAgent") is (role == "coordinator")
                        and data.get("subagent") is (role != "coordinator")
                        and data.get("commandExecutionPolicy") == "sandbox",
                        "unsafe_settings",
                    )
    except (
        OSError,
        UnicodeError,
        ValueError,
        TypeError,
        KeyError,
        AttributeError,
        yaml.YAMLError,
        RecursionError,
    ):
        return ["invalid_input"]
    return sorted(diagnostics)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--as-of", default=date.today().isoformat())
    args = parser.parse_args()
    try:
        as_of = date.fromisoformat(args.as_of)
        codes = validate_repository(args.root)
        if "invalid_input" in codes:
            print("invalid_input")
            return 2
        manifest = read_json(args.root / ".agent-models.json")
        reviewed = date.fromisoformat(manifest["reviewed_on"])
        if reviewed > as_of:
            print("invalid_input")
            return 2
        if review_due(reviewed, as_of, manifest["review_after_days"]):
            codes.append("model_review_due")
        for code in codes:
            print(code)
        return int(any(code != "model_review_due" for code in codes))
    except (ValueError, TypeError, KeyError, OSError, json.JSONDecodeError):
        print("invalid_input")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
