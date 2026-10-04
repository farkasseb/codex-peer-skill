---
name: codex-peer
description: "Run the OpenAI Codex CLI (codex exec) as a trusted peer for second opinions, reviews, or delegated work: investigating, fact-checking, implementing, running tests. Use only when Codex is named: \"ask codex\", \"have codex ...\", \"codex opinion\", or $codex-peer."
---

# Codex Peer

Codex is a trusted peer. Run it headless with `codex exec`, hand it a prompt
file, wait for the completion notification, and read its answer file. Verified
against codex-cli 0.160.0.

## Defaults

- `gpt-6-astra`, effort `medium`, fast tier, unless the user names others.
- **Review mode** (default): Codex reads anything on disk, runs commands, has
  network and live web search, and cannot write.
- **Work mode**, only when the task is to change files: the same, plus writes
  inside `-C`, `/tmp` and `$TMPDIR`.
- Both modes give Codex's commands a core environment
  (`shell_environment_policy.inherit="core"`). Without it they get every
  exported variable, tokens included, and Codex writes them in plain text to
  `~/.codex/shell_snapshots/`, where a killed run leaves them. `env -i` does
  not help: the snapshot shell reruns the user's startup files.
- Neither mode reaches the iOS Simulator: `xcrun simctl list` reports a lost
  CoreSimulator connection yet exits 0. Run simulator steps yourself.
- Pin model, effort, approvals and mode on every call, resume included.
  Anything omitted falls back to `~/.codex/config.toml`, which may set
  `workspace-write`, `on-request` approvals, or `low` effort.

## Run

Use the Bash tool from the main conversation with `run_in_background: true`.
A subagent tends to lose the job. Background tasks stop at 30 minutes by
default, so pass `timeout: 3600000` for `xhigh`, `max`, or long work.

Make a fresh run directory in your scratchpad, write the prompt to
`$RUN/prompt.md`, then:

```bash
codex exec -C /path/to/repo \
  -m gpt-6-astra -c 'model_reasoning_effort="medium"' -c 'service_tier="fast"' \
  -c 'approval_policy="never"' -c 'web_search="live"' \
  -c 'shell_environment_policy.inherit="core"' \
  -c 'default_permissions="peer"' -c 'permissions.peer.extends=":read-only"' \
  -c 'permissions.peer.network.enabled=true' \
  -o "$RUN/answer.md" - < "$RUN/prompt.md" > "$RUN/stdout.txt" 2> "$RUN/log.txt"
```

- For work mode, change `":read-only"` to `":workspace"`. Never add
  `--sandbox`: it overrides the profile and silently drops network.
- Give every `codex exec` its own stdin: `- < file`, a pipe, or `</dev/null`
  after a prompt argument. If the command text contains any `<`, Claude Code
  gives it a stdin that never closes, and an unredirected codex waits on it
  forever.
- Keep codex as the last command, unpiped. A trailing `| tee`, `| tail` or
  `; echo` reports exit 0 for a failed run.
- `-o` is written only when a run succeeds, and a failed run leaves an old file
  in place. Use a new path per run. Stdout carries the same final message.
- `-C` must be a git repository or a trusted project. Otherwise add
  `--skip-git-repo-check`.

## Pass data

- Prompts go in a file and through `- < file`, which avoids quoting and
  argument-size problems. A short prompt can be an argument with `</dev/null`.
- Give paths, not contents. Codex reads files outside `-C` too, and runs
  `git diff` or `git log` itself.
- A prompt argument plus piped data appends the data as a `<stdin>` block.
  `resume` silently drops it.
- `-i image.png` attaches images. `--output-schema schema.json` enforces the
  final message's JSON shape.
- Codex can read `~/.codex/auth.json` and other credentials in both modes.
  Tell it not to print them, and a work run not to copy them anywhere.

## Reviews

- Give the target, the facts and the open question. Leave out your own
  reasoning and the answer you expect, and never ask Codex to confirm a
  choice. "No issues" is a valid result.
- List the user's settled decisions under "Decisions already made (not open)",
  and check Codex's recommendations against them before relaying any.
- Start a fresh session for each review target. Resume only to re-review the
  same target after fixes.
- Stop when a round finds nothing serious. When the user asks for no
  bikeshedding, ask for critical findings only.

## Watch

- `tail -n 40 "$RUN/log.txt"` shows progress: an `exec` block per command and
  a `codex` block per message, after a banner with model, reasoning effort,
  sandbox and session id. After the run, check the banner's sandbox line with
  `head -n 12 "$RUN/log.txt"`. Review mode shows
  `read-only (network access enabled)`. Work mode shows
  `workspace-write [workdir, /tmp, $TMPDIR] (network access enabled)`.
- Silent minutes are normal while it reasons. Measured astra turns take a
  median 40 s at medium (p90 1.5 min), 3 min at high and 5 min at xhigh;
  `gpt-6.1-sol` at high takes about 8 min. The longest run seen took 47 min.
- Every event streams live to
  `~/.codex/sessions/YYYY/MM/DD/rollout-*-<session id>.jsonl`.
- Wait for the notification. Do not poll or wait for the banner with
  foreground `sleep` (2-minute Bash timeout) or with TaskOutput.
- Stop a run with TaskStop, which kills codex and its children. Killing the
  wrapper shell's PID orphans codex, and it keeps running.

## Follow up

```bash
codex exec -C /path/to/repo \
  -m gpt-6-astra -c 'model_reasoning_effort="medium"' -c 'service_tier="fast"' \
  -c 'approval_policy="never"' -c 'web_search="live"' \
  -c 'shell_environment_policy.inherit="core"' \
  -c 'default_permissions="peer"' -c 'permissions.peer.extends=":read-only"' \
  -c 'permissions.peer.network.enabled=true' \
  -o "$RUN/answer-2.md" resume <SESSION_ID> - < "$RUN/followup-2.md" \
  > "$RUN/stdout-2.txt" 2> "$RUN/log-2.txt"
```

- The session id is on the log's `session id:` line. With `--json`, it is the
  `thread_id` of the `thread.started` event.
- Resume keeps the conversation, not the settings. Model, effort, mode and
  approvals come from this call or the ambient config. Unpinned resumes have
  dropped to `low` effort and switched to workspace-write.
- `-C`, `--add-dir` and `-p` must come before `resume`; after it they exit 2.
  `-c`, `-m`, `-o` and `--json` work on either side.
- Do not use `resume --last` while runs overlap.

## Models

`codex debug models` prints the live catalog as one large JSON line. It is
safe to run in the foreground. List the models and their efforts with:

```bash
codex debug models | jq -r '.models[] | "\(.slug)\t\([.supported_reasoning_levels[].effort] | join(","))"'
```

| Model | Use |
|-------|-----|
| `gpt-6-astra` | Frontier model and the default |
| `gpt-6.1-sol` | Workhorse for everyday coding |
| `gpt-6-luna` | Fast and cheap. At low effort it may answer without reading files |

Efforts are `low`, `medium`, `high`, `xhigh` and `max`. `ultra` (astra and sol
only) adds automatic sub-agent delegation; use it only when asked. The CLI
accepts unsupported efforts without complaint, so check the catalog. Do not
switch models after a failure without asking.

## When it fails

| Symptom | Cause | Fix |
|---------|-------|-----|
| Log stuck at `Reading additional input from stdin...`, no banner | stdin left open | Redirect stdin on every call |
| Exit 2, `unexpected argument` | Flag after `resume`, or a flag `exec` lacks (`--search`, `-q`) | Move it before `resume`; check `codex exec --help` |
| Exit 1, 400 `model is not supported when using Codex with a ChatGPT account` | Model not in the catalog | Choose from `codex debug models` |
| Exit 1, `Not inside a trusted directory` | `-C` is not a git repository | `--skip-git-repo-check` |
| Files edited during a review, or a resume switched sandbox | Mode flags omitted, so ambient workspace-write applied | Pin the mode on every call; check the banner |
| `Could not resolve host` | No network: profile flags missing, or `--sandbox` overrode them | Profile flags only, no `--sandbox` |
| Exit 0 but no answer | Output piped, or another command ran after codex | Codex last, unpiped |
| Task killed at 30 min | Default background timeout | `timeout: 3600000` or more |
| A run launched from a subagent never reports | Subagent lost the background job | Launch from the main conversation |
| 401, `Reconnecting... 5/5` | Authentication | `codex login status`; ask the user to run `! codex login` |
| Denied before running | The permission classifier blocked it | Report the denial instead of working around it |

Report a failed run as failed, and never fill in what Codex probably said.
Check material claims before acting on or relaying them: code claims against
the repository, external facts such as law, tax, health or prices against a
primary source. Call a claim verified only after a check you ran; otherwise
attribute it to Codex.

## Maintenance

After a CLI update, run `./test_skill.sh` for static checks against the
installed CLI. In the background, run `./test_skill.sh --live`, which executes
the documented commands on a cheap model.
