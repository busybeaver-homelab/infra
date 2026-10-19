# Third-Party Notices

This repository is published for reference under an all-rights-reserved notice (see `LICENSE`). The third-party components below are redistributed under their own licences, which continue to apply to them.

Vendored agent skills are tracked in `skills-lock.json`. Every entry there must be listed here; a bats test enforces this.

| Component                       | Path                                      | Upstream                                                    | Licence | Notes                                                                                                       |
| ------------------------------- | ----------------------------------------- | ----------------------------------------------------------- | ------- | ----------------------------------------------------------------------------------------------------------- |
| agent-ci                        | `.agents/skills/agent-ci/`                | `redwoodjs/agent-ci`                                        | MIT     | Declared in the skill's `SKILL.md`; the upstream repository licence is not classified by GitHub.            |
| ansible-automation              | `.agents/skills/ansible-automation/`      | `aj-geddes/useful-ai-prompts`                               | MIT     | Upstream repository licence.                                                                                |
| bash-defensive-patterns         | `.agents/skills/bash-defensive-patterns/` | `wshobson/agents`                                           | MIT     | Upstream repository licence.                                                                                |
| gh                              | `.agents/skills/gh/`                      | `cli/cli`                                                   | MIT     | Upstream repository licence.                                                                                |
| gh-stack                        | `.agents/skills/gh-stack/`                | `github/gh-stack`                                           | MIT     | Upstream repository licence.                                                                                |
| mise-configuration              | `.agents/skills/mise-configuration/`      | `terrylica/cc-skills`                                       | MIT     | Upstream repository licence.                                                                                |
| mise-tasks                      | `.agents/skills/mise-tasks/`              | `terrylica/cc-skills`                                       | MIT     | Upstream repository licence.                                                                                |
| opentofu                        | `.agents/skills/opentofu/`                | `oakoss/agent-skills`                                       | MIT     | Declared in the skill's `SKILL.md`; the upstream repository is no longer reachable (provenance unverified). |
| uv-package-manager              | `.agents/skills/uv-package-manager/`      | `wshobson/agents`                                           | MIT     | Upstream repository licence.                                                                                |
| Antigravity Superpowers profile | `.agent/`                                 | `antigravity-superpowers` (derived from `obra/superpowers`) | MIT     | Licence of `obra/superpowers`.                                                                              |

Copyright for each component belongs to its respective authors.
