---
name: foundry-deploy
description: Run or preview a Foundry project on its test server - per-stack run commands, assigned ports from 8101, and *.foundry.test URLs via Caddy. Use when a stage needs the app running, or to check a project on its test URL. The Foundry owns the test server; never touch production or client credentials.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# foundry-deploy

Projects live in `~/projects/<slug>` on the Yoga. Each project has an assigned test port (from 8101, one per project) and a test URL: direct `http://100.79.96.4:<port>` and, once Caddy has a vhost, `http://<slug>.foundry.test`. Plain HTTP only. The Foundry owns the test server — its port, PID file (`storage/app/servers/<slug>.pid` in the dashboard), and Caddy vhost. Nothing here is production: never touch production or client credentials, and never put a secret in a command, a plan, or a log.

## Workflow

1. **Find the port and URL.** Read the project's `test_port` from the dashboard (project page) — never guess a port or reuse another project's. Verify the server answers: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:<port>/`.
2. **Laravel.** The Foundry auto-starts `php artisan serve --host=0.0.0.0 --port=<port>` — do not start a second one. Run migrations with `php artisan migrate` in the project dir. MySQL is provisioned per project when the plan says so (database `foundry_<slug>`, `DB_CONNECTION=mysql` in `.env`) — never switch it to SQLite.
3. **Node.** The Foundry reserves the port but does not start the server. Start the app yourself on the assigned port: `PORT=<port> node index.js` (the starter listens on `process.env.PORT || 8101`). Install deps first: `npm install`. Run `npm test` if a test script exists.
4. **Python.** No server is started by the Foundry. Set up the env once: `python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt`. Run `python main.py`; a web stage serves on the assigned port (pass the port through, e.g. `--port <port>` or a `PORT` env var, as the framework expects).
5. **Flutter, Godot, Tauri — "serves" is different.** Flutter web: `flutter run -d web-server --web-port=<port>` (HTTP on the assigned port; a mobile build has no test URL). Godot: export the web build, then serve the exported directory over HTTP on the assigned port. Tauri: a desktop app — `npm run tauri dev` opens a window, there is no HTTP test URL; preview is the built app. All three are placeholders in the Foundry until their SDKs are installed (see the stack skills).
6. **Never manage the server from inside a stage.** Do not stop, restart, or move the Foundry-tracked test server, and do not change its port. If it is down, report it with the server log (`storage/app/servers/<slug>.log`) — the Foundry restarts it.
7. **Keep credentials out.** Env values are set in the Foundry, never in plans or commands. If a run needs a credential that is not in the project's `.env`, stop and say which name is missing — do not paste a value in.
