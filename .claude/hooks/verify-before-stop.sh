#!/usr/bin/env bash
# verify-before-stop.sh - Claude Code Stop-hook script for Foundry projects.
#
# Purpose: never let Claude Code stop (and the stage be marked done) while
# the project's tests are failing. When the test suite fails, this script
# exits 2, which BLOCKS the stop in Claude Code and sends the failure
# output back so the agent keeps working on the fix.
#
# Install (done by another stream - this file is only the script):
#   in the project's .claude/settings.json:
#   {
#     "hooks": {
#       "Stop": [
#         { "hooks": [
#           { "type": "command",
#             "command": "<dashboard-repo>/scripts/verify-before-stop.sh" }
#         ] }
#       ]
#     }
#   }
#   (Use the absolute path to this script. Claude runs the hook with its
#   working directory set to the project directory.)
#
# Behaviour:
#   - Reads the hook JSON payload on stdin (Claude Code sends it there).
#   - When "stop_hook_active" is true, exits 0 IMMEDIATELY. Claude Code
#     caps consecutive blocks (currently ~8); honouring the flag is what
#     stops this hook looping forever when the agent cannot fix the tests.
#   - Otherwise runs the stack-aware test suite via verify-stage.sh
#     (same defaults: Laravel `php artisan test`, Node `npm test` when a
#     test script exists, Python `python3 -m pytest -q` when pytest config
#     is present; no tests detected counts as a pass).
#   - Exit 0 when tests pass or no tests exist. Exit 2 with the failure
#     output when tests fail (exit 2 is what blocks the stop).
#   - If verify-stage.sh is missing/unusable, exits 0: a missing tool
#     must not block the agent from stopping.
set -u

INPUT=$(cat)

# stop_hook_active: true means Claude Code already blocked this stop
# repeatedly - never block again, exit 0 right away.
if command -v python3 >/dev/null 2>&1; then
  ACTIVE=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("stop_hook_active") is True and "true" or "")' 2>/dev/null || echo '')
  CWD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cwd") or "")' 2>/dev/null || echo '')
else
  ACTIVE=$(printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && echo true || echo '')
  CWD=""
fi
if [ "$ACTIVE" = "true" ]; then
  exit 0
fi

DIR="${CWD:-$PWD}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERIFY_SCRIPT="$SCRIPT_DIR/verify-stage.sh"
if [ ! -x "$VERIFY_SCRIPT" ]; then
  exit 0
fi

OUT=$("$VERIFY_SCRIPT" "$DIR" 2>&1)
CODE=$?
if [ "$CODE" -ne 0 ]; then
  printf '%s\n' "$OUT"
  exit 2
fi
exit 0
