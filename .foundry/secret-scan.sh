#!/usr/bin/env bash
# Foundry secret scan — pre-push / staged-change guard.
#
# Scans staged changes (`git diff --cached`) for secret patterns and for
# sensitive filenames being added (.env, *.pem, *.key, credentials*).
# With --pre-push it ALSO scans the diff of the range being pushed (the
# ref lines git feeds a pre-push hook on stdin), because by push time
# everything is already committed and the staged diff is empty — scanning
# only staged changes at pre-push time would be a no-op.
#
# Prints only the filename, line number and pattern NAME — never the
# matched secret value itself. Exit 1 on any match, 0 otherwise (and 0
# when there is nothing staged, when not in a git repo, or when the
# scanner itself cannot run — a broken scanner must not brick pushes).
set -u

FOUND=0

report() { # report <file> <line> <pattern-name>
    printf 'SECRET-SCAN: %s:%s: matched %s\n' "$1" "$2" "$3"
    FOUND=1
}

# Check one added line against the secret patterns. One report per line,
# first match wins. Never prints the matched text, only the label.
check_line() { # check_line <file> <lineno> <content>
    local file="$1" lineno="$2" content="$3"
    # Fast path: most added lines mention no secret indicator at all --
    # one grep instead of a dozen per line. A full scaffold push scans
    # ~10k added lines (composer.lock alone); without this the pre-push
    # hook takes minutes. This is a superset of the patterns below, so
    # it can only skip lines no later check could match.
    if ! printf '%s' "$content" | grep -qiE 'AKIA[0-9A-Z]{16}|ghp_|sk-|private[_-]?key|api[_-]?key|password|secret|token'; then return; fi
    # Structured tokens first (case-sensitive).
    if printf '%s' "$content" | grep -qE 'AKIA[0-9A-Z]{16}'; then report "$file" "$lineno" 'aws-access-key-id (AKIA...)'; return; fi
    if printf '%s' "$content" | grep -qE 'ghp_[A-Za-z0-9]{20,}'; then report "$file" "$lineno" 'github-token (ghp_...)'; return; fi
    if printf '%s' "$content" | grep -qE 'sk-[A-Za-z0-9]{20,}'; then report "$file" "$lineno" 'secret-key (sk-...)'; return; fi
    # Stock syntax that is NOT a secret (B3): a quoted array/object key
    # whose value is a function call, variable, constant or expression
    # ('password' => env('DB_PASSWORD'), 'secret' => env(...),
    # 'remember_token' => Str::random(10), 'password' => static::$password
    # ??= Hash::make('password')) -- the value is computed, not a literal
    # credential. A quoted literal value ('password' => 'hunter2') is NOT
    # skipped here and still blocks below.
    if printf '%s' "$content" | grep -qiE "['\"][A-Za-z0-9_-]*(password|secret|token|api[_-]?key|private[_-]?key)['\"][[:space:]]*(=>|:)[[:space:]]*[^'\"[:space:]]"; then return; fi
    # Eloquent cast marker: 'password' => 'hashed' is stock Laravel, not a credential.
    if printf '%s' "$content" | grep -qiE "['\"]password['\"][[:space:]]*=>[[:space:]]*['\"]hashed['\"]"; then return; fi
    # An explicitly null assigned value is a placeholder, not a secret
    # (REDIS_PASSWORD=null, MAIL_PASSWORD=null in .env.example). Anchored
    # to end-of-line so a line carrying a second, real assignment later
    # is still scanned.
    if printf '%s' "$content" | grep -qiE '(password|secret|token|api[_-]?key)[^[:alnum:]_]?[[:space:]]*[:=][[:space:]]*null[[:space:]]*[,;]?[[:space:]]*$'; then return; fi
    # Keywords (case-insensitive). An assignment only counts when a real
    # value follows the operator: the value must start with a character
    # that is not a space, a quote, or an interpolation marker ($, %).
    # That excludes empty placeholders (DB_PASSWORD= in .env.example),
    # empty quoted values (DB_PASSWORD=''), variable references
    # (TOKEN=$FOO) and Apache interpolation (X-XSRF-Token:%{HTTP:...} in
    # public/.htaccess), while 'password' => 'hunter2' still blocks (the
    # '>' of '=>' satisfies the value check, and the literal is caught).
    if printf '%s' "$content" | grep -qiE 'private[_-]?key'; then report "$file" "$lineno" 'keyword private-key'; return; fi
    if printf '%s' "$content" | grep -qiE "api[_-]?key[^[:alnum:]_]?[[:space:]]*[:=][[:space:]]*[^[:space:]'\"%\$]"; then report "$file" "$lineno" 'keyword api-key'; return; fi
    if printf '%s' "$content" | grep -qiE "password[^[:alnum:]_]?[[:space:]]*[:=][[:space:]]*[^[:space:]'\"%\$]"; then report "$file" "$lineno" 'keyword password'; return; fi
    if printf '%s' "$content" | grep -qiE "secret([-_]?(key|value|token))?[^[:alnum:]_]?[[:space:]]*[:=][[:space:]]*[^[:space:]'\"%\$]"; then report "$file" "$lineno" 'keyword secret'; return; fi
    if printf '%s' "$content" | grep -qiE "token[^[:alnum:]_]?[[:space:]]*[:=][[:space:]]*[^[:space:]'\"%\$]"; then report "$file" "$lineno" 'keyword token'; return; fi
}
# Scan one unified diff (with -U0) for added lines. $1 = file holding the diff.
scan_diff() {
    local diff_file="$1" file='' lineno=0 line=''
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            '+++ b/'*)
                file="${line#+++ b/}"
                # The scanner never scans itself: this file's own source
                # (its comments and grep patterns) mentions keywords like
                # 'password' => ... and 'private-key', which would match
                # its own patterns and block every first push. The file
                # is Foundry-managed infrastructure, not project code.
                [ "$file" = '.foundry/secret-scan.sh' ] && file=''
                ;;
            '+++ /dev/null') file='' ;;
            '@@ '*)
                # @@ -a,b +START[,n] @@ — new-file line number starts at START.
                lineno="${line#*+}"
                lineno="${lineno%%[, ]*}"
                lineno=$((lineno - 1))
                ;;
            '+'*)
                if [ -n "$file" ]; then
                    lineno=$((lineno + 1))
                    check_line "$file" "$lineno" "${line#+}"
                fi
                ;;
        esac
    done < "$diff_file"
}

is_zero_sha() { # true when $1 is all zeros (any length)
    case "$1" in *[!0]*) return 1 ;; *) return 0 ;; esac
}

# Merge-base of a pushed sha with the default branch: the branch's fork
# point. Prints the base sha, or nothing when there is no fork point
# (no default branch resolves, or the tip IS the fork point -- first push
# of the repo's only branch, where the branch's own diff is the whole
# tree). Local refs first: a stage worktree's fork point is local main.
merge_base_for() { # merge_base_for <sha>
    local ref base
    for ref in main master origin/main origin/master; do
        base="$(git merge-base "$1" "$ref" 2>/dev/null)" || continue
        [ -n "$base" ] && [ "$base" != "$1" ] && { printf '%s' "$base"; return 0; }
    done
    return 1
}

# Not a git repo (or git missing) -> nothing to scan, do not block.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. Staged changes.
if git diff --cached --unified=0 --no-color --no-ext-diff > "$WORK/staged.diff" 2>/dev/null; then
    scan_diff "$WORK/staged.diff"
fi

# 2. Sensitive filenames being added (staged).
git diff --cached --name-only --diff-filter=A 2>/dev/null > "$WORK/added.txt" || true
while IFS= read -r added || [ -n "$added" ]; do
    [ -z "$added" ] && continue
    base="$(basename "$added")"
    case "$base" in
        .env) report "$added" 0 'blocked filename (.env)' ;;
        *.pem) report "$added" 0 'blocked filename (*.pem)' ;;
        *.key) report "$added" 0 'blocked filename (*.key)' ;;
        credentials*) report "$added" 0 'blocked filename (credentials*)' ;;
    esac
done < "$WORK/added.txt"

# 3. Pre-push range scan: diff each pushed ref range (stdin ref lines).
if [ "${1:-}" = "--pre-push" ] && [ ! -t 0 ]; then
    EMPTY_TREE="$(git hash-object -t tree /dev/null 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)"
    # NOTE: no IFS= here — default splitting must put the four fields
    # into the four variables (IFS= would dump the whole line into the first).
    while read -r local_ref local_sha remote_ref remote_sha || [ -n "${local_ref:-}" ]; do
        [ -z "${local_sha:-}" ] && continue
        if is_zero_sha "$local_sha"; then continue; fi  # branch deletion: nothing pushed
        if is_zero_sha "${remote_sha:-0000000000000000000000000000000000000000}"; then
            # New branch: diff against the fork point (merge-base with the
            # default branch), so only the branch's OWN commits are
            # scanned. Diffing against the empty tree scanned the whole
            # repo and false-positived on every stock file that mentions
            # a keyword. When there is no fork point (first push of the
            # repo's only branch) the branch's own diff IS the whole tree,
            # so the empty tree stays correct there.
            base="$(merge_base_for "$local_sha" || echo "$EMPTY_TREE")"
        else
            base="$remote_sha"
        fi
        if git diff --unified=0 --no-color --no-ext-diff "$base" "$local_sha" > "$WORK/range.diff" 2>/dev/null; then
            scan_diff "$WORK/range.diff"
        fi
    done
fi

if [ "$FOUND" -ne 0 ]; then
    printf 'SECRET-SCAN: blocked - secrets or sensitive files detected. Remove them from the change and retry.\n' >&2
    exit 1
fi
exit 0
