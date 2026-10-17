## Summary

<!-- Concise summary of the changes and architectural rationale. Cite applicable STD-* or R2-* rule IDs. -->

## Changed Files (`git diff --stat main...HEAD`)

```text
<!-- Paste exact output of: git diff --stat main...HEAD -->
```

## Tests Run

| Command                                         | Exit Code | Result Summary                      |
| :---------------------------------------------- | :-------: | :---------------------------------- |
| `mise exec lefthook -- lefthook run pre-commit` |    `0`    | <!-- e.g. All hooks passed -->      |
| `mise exec -- bats tests/scripts/`              |    `0`    | <!-- e.g. All bats tests passed --> |

## Verification & Governance Checklist

### Referenced Files Exist

- [ ] Every file path, test name, and count mentioned in this PR description was copied from command output in the same session and verified to exist in the branch (`git diff --stat main...HEAD`).
- [ ] No sensitive information (decrypted secrets, internal IPs, subnets, internal hostnames, or server domains) appears in the PR title, description, or commits.
- [ ] Automated tests (`.bats`, `.tftest.hcl`, or Molecule) were added or updated for all new or changed functionality.
- [ ] Task tracker (`docs/plans/task.md`) was archived to `docs/plans/archive/task-<YYYY-MM-DD>-<topic>.md` and any status tracker rows marked `Done` include the commit SHA and verification command.
