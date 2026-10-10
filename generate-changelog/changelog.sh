#!/usr/bin/env bash
#
# changelog.sh — Generate a structured CHANGELOG from git history.
#
# Fetches commits since the most recent git tag (or the entire history if no
# tag exists) and auto-categorizes them into Added / Fixed / Changed / Removed
# based on Conventional-Commit prefixes and sensible keyword heuristics, then
# writes a Keep-a-Changelog formatted CHANGELOG.md.
#
# Usage:
#   bash changelog.sh                 # write/prepend to ./CHANGELOG.md
#   bash changelog.sh -o OUT.md       # write to a specific file
#   bash changelog.sh --stdout        # print to stdout, write nothing
#   bash changelog.sh --since v1.2.0  # categorize commits since a given ref
#   bash changelog.sh --version 1.3.0 # label the generated section (default: next tag guess)
#   bash changelog.sh -h | --help
#
# Exit codes: 0 ok, 1 usage error, 2 not a git repo / git failure.
set -euo pipefail

OUT="CHANGELOG.md"
TO_STDOUT=0
SINCE=""
VERSION=""

die()  { printf 'error: %s\n' "$1" >&2; exit "${2:-1}"; }
usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output)  OUT="${2:-}"; [ -n "$OUT" ] || die "missing value for $1"; shift 2 ;;
    --stdout)     TO_STDOUT=1; shift ;;
    --since)      SINCE="${2:-}"; [ -n "$SINCE" ] || die "missing value for $1"; shift 2 ;;
    --version)    VERSION="${2:-}"; [ -n "$VERSION" ] || die "missing value for $1"; shift 2 ;;
    -h|--help)    usage ;;
    *)            die "unknown argument: $1" ;;
  esac
done

command -v git >/dev/null 2>&1 || die "git is not installed" 2
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository" 2

# Determine the range: everything since the last tag, unless --since was given.
if [ -z "$SINCE" ]; then
  if LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null)"; then
    SINCE="$LAST_TAG"
  else
    SINCE=""   # no tags -> use full history
  fi
fi

if [ -n "$SINCE" ]; then
  RANGE="${SINCE}..HEAD"
else
  RANGE="HEAD"
fi

# Guess the next version label if none supplied.
if [ -z "$VERSION" ]; then
  if [ -n "$SINCE" ] && printf '%s' "$SINCE" | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+$'; then
    base="${SINCE#v}"
    IFS='.' read -r MA MI PA <<EOF
$base
EOF
    VERSION="${MA}.${MI}.$((PA + 1))"
  else
    VERSION="Unreleased"
  fi
fi

DATE="$(date +%Y-%m-%d)"

# Collect commit subjects. %s = subject only; keep it deterministic.
COMMITS="$(git log --no-merges --pretty=format:'%s' "$RANGE" 2>/dev/null || true)"

ADDED=""; FIXED=""; CHANGED=""; REMOVED=""

add_line() { # $1=bucket-name $2=text
  local line="- $2"
  case "$1" in
    added)   ADDED="${ADDED}${line}"$'\n' ;;
    fixed)   FIXED="${FIXED}${line}"$'\n' ;;
    changed) CHANGED="${CHANGED}${line}"$'\n' ;;
    removed) REMOVED="${REMOVED}${line}"$'\n' ;;
  esac
}

categorize() { # $1 = raw subject -> echoes bucket name
  local s="$1"
  local lower; lower="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"

  # Conventional Commit types take priority (optional scope + optional !).
  case "$lower" in
    feat*)                      echo added;   return ;;
    fix*|bugfix*|hotfix*)       echo fixed;    return ;;
    revert*)                    echo removed;  return ;;
    perf*|refactor*|style*|build*|ci*|chore*|docs*|test*) echo changed; return ;;
  esac

  # Keyword heuristics for non-conventional messages.
  case "$lower" in
    add\ *|added\ *|adds\ *|new\ *|introduce*|implement*|create\ *|support\ *) echo added;   return ;;
    fix\ *|fixed\ *|fixes\ *|resolve*|patch\ *|correct*|repair*)               echo fixed;    return ;;
    remove*|removed\ *|removes\ *|delete*|drop\ *|deprecate*)                   echo removed;  return ;;
    *)                                                                         echo changed;  return ;;
  esac
}

# Normalize a subject for display: strip a leading conventional-commit prefix
# like "feat(scope): " / "fix!: " so the changelog reads cleanly.
clean_subject() { # $1 = raw subject
  printf '%s' "$1" | sed -E 's/^[a-zA-Z]+(\([^)]*\))?!?:[[:space:]]*//'
}

# Capitalize the first character. Portable (no GNU-only `sed \U`): uses
# bash parameter expansion + tr, which works on bash 3.2 (macOS) and up.
capitalize() { # $1 = text
  local t="$1"
  [ -n "$t" ] || { printf ''; return; }
  local first="${t:0:1}"
  local rest="${t:1}"
  printf '%s%s' "$(printf '%s' "$first" | tr '[:lower:]' '[:upper:]')" "$rest"
}

if [ -n "$COMMITS" ]; then
  while IFS= read -r subject; do
    [ -n "$subject" ] || continue
    bucket="$(categorize "$subject")"
    text="$(clean_subject "$subject")"
    text="$(capitalize "$text")"
    add_line "$bucket" "$text"
  done <<EOF
$COMMITS
EOF
fi

emit_section() { # $1=heading $2=body
  [ -n "$2" ] || return 0
  printf '### %s\n%s\n' "$1" "$2"
}

NEW_SECTION="$(
  printf '## [%s] - %s\n\n' "$VERSION" "$DATE"
  if [ -z "$ADDED$FIXED$CHANGED$REMOVED" ]; then
    printf '_No categorized changes found in range %s._\n\n' "$RANGE"
  else
    emit_section "Added"   "$ADDED"
    emit_section "Changed" "$CHANGED"
    emit_section "Fixed"   "$FIXED"
    emit_section "Removed" "$REMOVED"
  fi
)"

HEADER="$(cat <<'HDR'
# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

HDR
)"

if [ "$TO_STDOUT" -eq 1 ]; then
  printf '%s\n%s\n' "$HEADER" "$NEW_SECTION"
  exit 0
fi

# Prepend the new section under the header, preserving any existing sections.
if [ -f "$OUT" ] && grep -q '^## ' "$OUT" 2>/dev/null; then
  EXISTING="$(awk '/^## /{p=1} p{print}' "$OUT")"
  printf '%s\n%s\n\n%s\n' "$HEADER" "$NEW_SECTION" "$EXISTING" > "$OUT"
else
  printf '%s\n%s\n' "$HEADER" "$NEW_SECTION" > "$OUT"
fi

printf 'Wrote %s (version %s, range %s)\n' "$OUT" "$VERSION" "$RANGE" >&2
