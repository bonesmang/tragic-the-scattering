#!/usr/bin/env bash
# verify-stage.sh - canonical executable verification definition for Foundry.
#
# The SAME script is called by two runners:
#   - the Foundry dashboard (VerificationService runs per-stage commands
#     itself, but this script is the executable form of the stack
#     defaults below, for local runs and debugging), and
#   - GitHub Actions CI (e.g. `.github/workflows/verify.yml`, calling
#     `./scripts/verify-stage.sh .`).
#
# Usage:
#   scripts/verify-stage.sh <project-dir>
#
# Stack defaults (one stack per project, detected by marker files):
#   Laravel:  php artisan test            (requires artisan in the dir)
#   Node:     npm test                    (only when package.json has a
#                                          "test" script, else exit 0)
#   Python:   python3 -m pytest -q       (only when pytest config is
#                                          present: pytest.ini, pyproject.toml
#                                          or setup.cfg, else exit 0)
#   Other / no tests detected: exit 0 with a note - there is nothing to run.
#
# Exit codes: 0 = tests passed (or no tests exist), non-zero = the test
# command's own exit code. Output is the test command's output, unedited.
# Per-stage custom commands and HTTP checks are NOT handled here - the
# PHP VerificationService is the source of truth for those; this script
# covers the stack defaults only.
set -u

DIR="${1:-}"
if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
  echo "verify-stage: usage: verify-stage.sh <project-dir>" >&2
  exit 1
fi
cd "$DIR" || exit 1

has_npm_test() {
  # Node present: ask it. Otherwise fall back to a grep for a "test" script.
  if command -v node >/dev/null 2>&1; then
    node -e "const p=require('./package.json'); process.exit(p.scripts && p.scripts.test ? 0 : 1)" 2>/dev/null
  else
    grep -q '"test"[[:space:]]*:' package.json 2>/dev/null
  fi
}

if [ -f artisan ]; then
  exec php artisan test
elif [ -f package.json ] && has_npm_test; then
  exec npm test
elif [ -f pytest.ini ] || [ -f pyproject.toml ] || [ -f setup.cfg ]; then
  exec python3 -m pytest -q
else
  echo "verify-stage: no test suite detected in $DIR - nothing to verify."
  exit 0
fi
