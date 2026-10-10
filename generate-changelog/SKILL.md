---
name: generate-changelog
description: Generate a structured, Keep-a-Changelog formatted CHANGELOG.md from a project's git history. Fetches commits since the last git tag and auto-categorizes them into Added / Changed / Fixed / Removed.
---

# Generate Changelog

Use this skill when the user asks to **create, update, or regenerate a CHANGELOG**
from git history, or runs the `/generate-changelog` command.

## What it does

Reads the repository's git log since the most recent tag (or the full history if
there are no tags) and produces a `CHANGELOG.md` that follows the
[Keep a Changelog](https://keepachangelog.com/) convention, with commits sorted
into four sections:

- **Added** — new features (`feat:`, "add", "implement", "support", …)
- **Changed** — refactors, perf, docs, chores, style, build, ci (`refactor:`, `perf:`, `chore:`, …)
- **Fixed** — bug fixes (`fix:`, "resolve", "patch", "correct", …)
- **Removed** — deletions / reverts / deprecations (`revert:`, "remove", "drop", "deprecate", …)

Conventional-Commit prefixes (`feat(scope)!: …`) are detected first and stripped
from the rendered line; plain-English messages fall back to keyword heuristics.

## How to run

A single dependency-free bash script does the work (`changelog.sh`, bundled next
to this file). From the repository root:

```bash
# Write/prepend a new section to ./CHANGELOG.md (default):
bash changelog.sh

# Preview without writing anything:
bash changelog.sh --stdout

# Categorize commits since a specific tag/ref, label the section explicitly:
bash changelog.sh --since v1.2.0 --version 1.3.0

# Write to a custom path:
bash changelog.sh -o docs/CHANGELOG.md
```

### Options

| Flag | Description |
|------|-------------|
| `-o, --output FILE` | Output file (default `CHANGELOG.md`). |
| `--stdout` | Print to stdout; write nothing. |
| `--since REF` | Categorize commits since this tag/ref (default: last tag, else full history). |
| `--version X.Y.Z` | Label for the generated section (default: auto-bump patch from last tag, else `Unreleased`). |
| `-h, --help` | Show usage. |

## Behavior notes

- Merge commits are skipped (`--no-merges`).
- If no new commits are found in the range, the section is still emitted with a
  clear `_No categorized changes found_` note so the run is never silently empty.
- When `CHANGELOG.md` already exists, the new version section is **prepended**
  above the previous sections (the header is regenerated once at the top).
- The script uses only `git`, `sed`, `awk`, and `tr` — no network, no extra deps.

## When NOT to use

- If the project already has an automated changelog pipeline (e.g.
  `semantic-release`, `changesets`, `git-cliff`) — defer to that instead.
