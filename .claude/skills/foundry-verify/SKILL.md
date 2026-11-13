---
name: foundry-verify
description: Verify a Foundry stage the way the dashboard does - run the plan's verification block (or stack defaults), read the verification log, and report every acceptance criterion as passed with quoted evidence or 'not verified'. Use when a stage finishes, when verification fails, or when you must judge whether a stage is actually done. Never mark an un-run criterion 'passed'.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# foundry-verify

After `claude -p` exits, the Foundry dashboard runs the canonical verification script `scripts/verify-stage.sh` (dashboard repo, `~/projects/factory-dashboard/scripts/verify-stage.sh`) plus HTTP checks against the stage's test server. A Stop hook, `scripts/verify-before-stop.sh`, blocks the agent from stopping while tests fail. Both scripts are owned by the verification stream — they are external to this skill. If either script is missing, verification has not landed yet: say so, run the plan's commands by hand, and do not write your own copy of the script.

## Workflow

1. **Find the verification block.** Read the stage's `verification` block in `foundry-plan.json`: the commands to run and the HTTP checks to make (`commands` run from the project dir after the stage; `http_checks` are `{path, expect_status}` pairs probed against the test URL). If the stage has no block, use the stack defaults: Laravel `php artisan test`; Node `npm test` (only if a `test` script exists in `package.json`).
2. **Read the verification log.** The dashboard appends verification output to the stage build log, `~/projects/factory-dashboard/storage/app/builds/stage-<stage_id>-build-<id>.log`. Read the verification section at the end — exit code first, then the failing lines.
3. **Check the HTTP checks.** Each check is a request against the test server on `127.0.0.1:<port>` (the project's assigned test port, from 8101). Each check names a `path` and an `expect_status` (usually 200). A connection refusal means the server is down, not that the check failed — say which.
4. **Respect the Stop hook.** If `verify-before-stop.sh` blocked the stop, the stage is not done. Fix the failing tests and re-run; never work around the hook, silence it, or declare victory while it fails.
5. **Judge every acceptance criterion.** For each criterion in the stage, quote the evidence: the passing test name, the log line, or the HTTP status. A criterion with no evidence is `not verified` — never `passed`.
6. **Classify a failure before fixing.** Test assertion failed (code wrong) vs environment failed (server down, port wrong, database unreachable, dependency missing). Environment failures are fixed in setup, not by editing app code to suit the environment.
7. **Watch the MySQL trap.** A Laravel stage whose plan says MySQL must verify against MySQL. If `.env` says `DB_CONNECTION=sqlite` or the provisioned database is unreachable, the database criteria are `not verified` — never re-point the app at SQLite to make tests pass.
8. **Report in this shape.** One line per criterion: `PASS | FAIL | NOT VERIFIED — <criterion> — <evidence>`. Then the verdict: stage verified, or stage not verified with the failing items listed.

## Reading a failed log

| What you see | What it usually means | Next step |
|---|---|---|
| A named test failed with an assertion | App code does not meet the criterion | Fix the code, re-run that test |
| `Connection refused` on 127.0.0.1:<port> | Test server is down | Check the server log (`storage/app/servers/<slug>.log`); do not change the port |
| Database connection error | Provisioned MySQL unreachable or `.env` wrong | Check `.env` and the database; never switch to SQLite |
| `npm test` / script missing | No test suite exists yet | Criterion is `not verified`; add tests before claiming it |
| Hook blocked the stop | Tests still failing at stop time | Fix and re-run; the hook is the gate, not the problem |
