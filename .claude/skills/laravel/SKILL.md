---
name: laravel
description: Build a Laravel stage in the Foundry - composer scaffold, artisan serve on the assigned port, migrations on provisioned MySQL, php artisan test. Use when a Foundry stage's stack is Laravel. Never switch a MySQL plan to SQLite.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# laravel

Laravel is the Foundry's first-class stack: the only one with a full scaffold and an auto-started test server. Stage 1 scaffolds; later stages build on it.

## Workflow

1. **Scaffold (stage 1 only).** The Foundry runs `composer create-project laravel/laravel <slug> --prefer-dist --no-interaction` in `~/projects/`. Never re-run it in a later stage — the app already exists.
2. **Serve.** The Foundry starts `php artisan serve --host=0.0.0.0 --port=<port>` and owns it. Check it with `curl http://127.0.0.1:<port>/`. Never start a second server or change the port.
3. **Database.** When the plan says MySQL, the Foundry provisions a real database (`foundry_<slug>` on `127.0.0.1:3306`) and points `.env` at it (`DB_CONNECTION=mysql`). Run `php artisan migrate` after adding migrations. Never switch to SQLite to make a test pass — a MySQL criterion verified on SQLite is `not verified`.
4. **Test.** `php artisan test` in the project dir. Feature tests go in `tests/Feature`, unit tests in `tests/Unit`. A stage that adds behaviour adds a test for it.
5. **Conventions.** Routes in `routes/web.php` / `routes/api.php`; models in `app/Models`; migrations in `database/migrations`; Blade views in `resources/views`. Keep `.env` out of git — it holds the provisioned database credentials.
6. **Done means.** `php artisan test` passes; migrations run clean against the provisioned MySQL; the app answers 200 on its test URL; every acceptance criterion has quoted evidence (see `foundry-verify`).
