#!/usr/bin/env python3
"""Convert ShellCheck JSON output to SARIF v2.1.0 format.

Reads ShellCheck JSON findings from standard input (or an optional file path)
and outputs a standard SARIF v2.1.0 JSON document to standard output suitable
for GitHub Code Scanning (upload-sarif).
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

SARIF_SCHEMA = "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json"
SARIF_VERSION = "2.1.0"

LEVEL_MAP: dict[str, str] = {
    "error": "error",
    "warning": "warning",
    "info": "note",
    "style": "note",
}


def parse_shellcheck_findings(raw_input: str) -> list[dict[str, Any]]:
    """Parse raw JSON input from ShellCheck into a list of findings."""
    cleaned = raw_input.strip()
    if not cleaned:
        return []

    try:
        data = json.loads(cleaned)
    except json.JSONDecodeError as err:
        sys.stderr.write(f"Warning: Failed to decode ShellCheck JSON: {err}\n")
        return []

    if isinstance(data, list):
        return [item for item in data if isinstance(item, dict)]

    if isinstance(data, dict) and "comments" in data:
        comments = data.get("comments")
        if isinstance(comments, list):
            return [item for item in comments if isinstance(item, dict)]

    return []


def normalize_path(file_path: str) -> str:
    """Normalize file path for SARIF artifactLocation."""
    norm = os.path.normpath(file_path)
    if norm.startswith("./"):
        norm = norm[2:]
    return norm


def convert_findings_to_sarif(findings: list[dict[str, Any]]) -> dict[str, Any]:
    """Convert parsed ShellCheck findings to a SARIF v2.1.0 structure."""
    results: list[dict[str, Any]] = []
    rules: dict[str, dict[str, Any]] = {}

    for finding in findings:
        code = finding.get("code")
        rule_id = f"SC{code}" if code is not None else "ShellCheck"
        level_raw = str(finding.get("level", "warning")).lower()
        level = LEVEL_MAP.get(level_raw, "warning")
        message_text = str(finding.get("message", "ShellCheck finding"))

        if rule_id not in rules:
            rules[rule_id] = {
                "id": rule_id,
                "name": rule_id,
                "shortDescription": {"text": message_text},
                "helpUri": (
                    f"https://www.shellcheck.net/wiki/{rule_id}"
                    if code is not None
                    else "https://www.shellcheck.net"
                ),
                "properties": {
                    "tags": ["bash", "shellcheck"],
                    "problem.severity": level,
                },
            }

        file_path = normalize_path(str(finding.get("file", "")))
        start_line = max(1, int(finding.get("line", 1)))
        end_line = max(start_line, int(finding.get("endLine", start_line)))
        start_col = max(1, int(finding.get("column", 1)))
        end_col = max(start_col, int(finding.get("endColumn", start_col)))

        result: dict[str, Any] = {
            "ruleId": rule_id,
            "level": level,
            "message": {"text": message_text},
            "locations": [
                {
                    "physicalLocation": {
                        "artifactLocation": {
                            "uri": file_path,
                            "uriBaseId": "%SRCROOT%",
                        },
                        "region": {
                            "startLine": start_line,
                            "startColumn": start_col,
                            "endLine": end_line,
                            "endColumn": end_col,
                        },
                    }
                }
            ],
        }
        results.append(result)

    return {
        "$schema": SARIF_SCHEMA,
        "version": SARIF_VERSION,
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "ShellCheck",
                        "informationUri": "https://www.shellcheck.net",
                        "rules": list(rules.values()),
                    }
                },
                "results": results,
            }
        ],
    }


def main() -> None:
    """Execute main entrypoint."""
    if len(sys.argv) > 1 and sys.argv[1] not in ("-", "--"):
        with Path(sys.argv[1]).open(encoding="utf-8") as f:
            raw_input = f.read()
    else:
        raw_input = sys.stdin.read()

    findings = parse_shellcheck_findings(raw_input)
    sarif_doc = convert_findings_to_sarif(findings)
    json.dump(sarif_doc, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
