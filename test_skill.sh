#!/usr/bin/env bash
#
# Drift check for the codex-peer skill.
#   ./test_skill.sh          static: frontmatter, command rules, flags and models vs the installed CLI
#   ./test_skill.sh --live   also runs SKILL.md's own commands on a cheap model (uses Codex quota)
#
# CODEX_PEER_TEST_MODEL overrides the live model (default gpt-6.1-sol at low effort).
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL="$DIR/SKILL.md"
FAIL=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; FAIL=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

case "${1:-}" in
  "") LIVE=0 ;;
  --live) LIVE=1 ;;
  *) printf 'Usage: %s [--live]\n' "$0" >&2; exit 2 ;;
esac

# Bash blocks in SKILL.md that call codex exec, NUL-separated.
blocks() {
  python3 -c '
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
for b in re.findall(r"```bash\n(.*?)```", text, re.S):
    if "codex exec" in b:
        sys.stdout.write(b + "\0")' "$SKILL"
}

printf -- '--- static ---\n'
check "frontmatter name is codex-peer" "grep -qx 'name: codex-peer' '$SKILL'"
check "description is 1-1024 chars" "python3 -c '
import re, sys
m = re.search(r\"^description: (.*)$\", open(sys.argv[1]).read(), re.M)
sys.exit(0 if m and 0 < len(m.group(1)) <= 1024 else 1)' '$SKILL'"
check "SKILL.md stays under 180 lines" "[ \$(wc -l < '$SKILL') -le 180 ]"
check "no home paths or emails" "! grep -qE '/User[s]/|/hom[e]/|[[:alnum:]._-]+@[[:alnum:]-]+\.[[:alpha:]]{2,}' '$SKILL' '$DIR/README.md'"

n=0; r=0
while IFS= read -r -d '' b; do
  n=$((n + 1))
  flat="$(printf '%s' "$b" | tr '\\\n' '  ' | tr -s ' ')"
  check "example $n: approval_policy never" "grep -qF 'approval_policy=\"never\"' <<<\"\$flat\""
  check "example $n: pins model and effort" "grep -qE -- '-m [^ ]+ .*model_reasoning_effort=' <<<\"\$flat\""
  check "example $n: uses the permission profile with network" \
    "grep -qF 'default_permissions=' <<<\"\$flat\" && grep -qF 'network.enabled=true' <<<\"\$flat\""
  check "example $n: core environment for commands" "grep -qF 'shell_environment_policy.inherit=\"core\"' <<<\"\$flat\""
  check "example $n: no --sandbox next to the profile" "! grep -qF -- '--sandbox' <<<\"\$flat\""
  check "example $n: redirects stdin" "grep -qE -- '(- <|</dev/null)' <<<\"\$flat\""
  check "example $n: codex output is not piped" "! grep -qE '\| *(tee|tail|head|cat)' <<<\"\$flat\""
  if grep -qw resume <<<"$flat"; then
    r=$((r + 1))
    pre="${flat%% resume *}"
    check "example $n: -C and profile come before resume" \
      "grep -qF -- '-C ' <<<\"\$pre\" && grep -qF 'default_permissions=' <<<\"\$pre\""
    check "example $n: resume reads the follow-up through -" "grep -qE 'resume [^ ]+ - <' <<<\"\$flat\""
  fi
done < <(blocks)
check "SKILL.md has a run and a resume example" "[ $r -ge 1 ] && [ $n -gt $r ]"

if command -v codex >/dev/null 2>&1; then
  help="$(codex exec --help 2>&1; codex exec resume --help 2>&1)"
  # Flags on the `unexpected argument` row are examples exec must reject.
  rejected="$(grep -F 'unexpected argument' "$SKILL" | grep -oE -- '`--?[a-z][a-z-]*`' | tr -d '`')"
  while IFS= read -r flag; do
    if grep -qxF -- "$flag" <<<"$rejected"; then
      check "exec still rejects: $flag" "! grep -qE -- '(^|[ ,])$flag([ ,=]|\$)' <<<\"\$help\""
    else
      check "exec accepts: $flag" "grep -qF -- '$flag' <<<\"\$help\""
    fi
  done < <({ grep -oE -- '(^|[ `(])--[a-z][a-z-]+' "$SKILL" | grep -oE -- '--[a-z-]+'; \
    printf '%s\n' "$rejected"; } | grep -vx -- '--live' | sort -u)
  catalog="$(codex debug models 2>/dev/null | python3 -c '
import json, sys
print("\n".join(m["slug"] for m in json.load(sys.stdin).get("models", [])))' 2>/dev/null)"
  if [ -n "$catalog" ]; then
    while IFS= read -r model; do
      check "model in codex debug models: $model" "grep -qxF '$model' <<<\"\$catalog\""
    done < <(grep -oE 'gpt-[0-9][a-z0-9.-]*[a-z0-9]' "$SKILL" | sort -u)
  else
    bad "codex debug models returned no catalog"
  fi
else
  bad "codex is not on PATH"
fi

if [ "$LIVE" -eq 1 ]; then
  model="${CODEX_PEER_TEST_MODEL:-gpt-6.1-sol}"
  printf -- '--- live (%s, low) ---\n' "$model"
  root="$(mktemp -d "${TMPDIR:-/tmp}/codex-peer-test.XXXXXX")"
  trap 'rm -Rf -- "$root"' EXIT
  git init -q "$root/repo"
  export RUN="$root/run"
  mkdir "$RUN"
  run_block() { # $1 block, $2 extra sed program; runs the block with test paths and model
    bash -c "$(printf '%s' "$1" | sed -e "s#/path/to/repo#$root/repo#g" \
      -e "s#-m gpt-[a-z0-9.-]*#-m $model#" \
      -e 's#model_reasoning_effort="[a-z]*"#model_reasoning_effort="low"#' -e "$2")"
  }
  run_ex=""; resume_ex=""
  while IFS= read -r -d '' b; do
    if grep -qw resume <<<"$b"; then resume_ex="$b"; else run_ex="$b"; fi
  done < <(blocks)

  printf '%s\n' "Run exactly: curl -sS -o /dev/null -w '%{http_code}' https://example.com" \
    "Then run exactly: echo \"\${CODEX_PEER_CANARY:-unset}\"" \
    "Reply with exactly PEER_OK, the curl output and the echo output, separated by spaces." \
    > "$RUN/prompt.md"
  CODEX_PEER_CANARY=leaked run_block "$run_ex" ''
  check "review run exits 0" "[ $? -eq 0 ]"
  check "review banner: read-only with network" "grep -qF 'sandbox: read-only (network access enabled)' '$RUN/log.txt'"
  check "review run reached the network" "grep -qF 'PEER_OK 200' '$RUN/answer.md'"
  check "caller's environment stays out of commands" "grep -qF 'PEER_OK 200 unset' '$RUN/answer.md'"

  sid="$(awk '/^session id:/ {print $3; exit}' "$RUN/log.txt")"
  printf '%s\n' "Repeat the exact token that started your previous reply. Reply with only that token." \
    > "$RUN/followup-2.md"
  run_block "$resume_ex" "s#<SESSION_ID>#$sid#"
  check "resume exits 0" "[ $? -eq 0 ]"
  check "resume recalled the first turn" "grep -qF 'PEER_OK' '$RUN/answer-2.md'"
  check "resume kept the restated read-only mode" "grep -qF 'sandbox: read-only (network access enabled)' '$RUN/log-2.txt'"

  printf '%s\n' "Use the shell to create probe.txt containing hi, then reply with exactly WORK_OK." \
    > "$RUN/prompt.md"
  rm -f "$RUN/answer.md"
  run_block "$run_ex" 's#":read-only"#":workspace"#'
  check "work run exits 0" "[ $? -eq 0 ]"
  check "work banner: workspace-write with network" \
    "grep -qE 'sandbox: workspace-write .*\(network access enabled\)' '$RUN/log.txt'"
  check "work run wrote inside -C" "[ -f '$root/repo/probe.txt' ]"
fi

printf '\n%s\n' "$([ "$FAIL" -eq 0 ] && echo 'ALL PASS' || echo 'FAILURES PRESENT')"
exit "$FAIL"
