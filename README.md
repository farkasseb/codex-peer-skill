# Codex Peer Skill

An agent skill for driving the OpenAI Codex CLI (`codex exec`) from Claude Code as a trusted peer. Codex handles second opinions, reviews, and delegated work such as investigating, fact-checking, implementing, and running tests.

The skill teaches the mechanics that agents keep getting wrong:

- the flags that pin model, effort, approvals and permissions;
- how to pass prompts and data;
- how to wait for and monitor a background run;
- how to resume a session;
- the failure modes that have actually happened.

## What it encodes

- **Two modes, both with network and live web search.** Review mode is read-only. Work mode can write inside the working root. Both use Codex permission profiles (`default_permissions`), the only way found to combine read-only with network. Adding `--sandbox` overrides the profile and silently drops network.
- **Core environment for commands.** By default Codex hands its commands every exported variable, API tokens included, and writes them in plain text to a shell snapshot under `~/.codex/shell_snapshots/`, which a killed run leaves behind. `shell_environment_policy.inherit="core"` trims the inherited set to `HOME`, `PATH`, locale and Codex's own variables, plus anything the user's `shell_environment_policy.set` adds. Launching Codex under `env -i` does not help: its snapshot shell runs the user's shell startup files, which can export secrets of their own.
- **Reviews that can disagree.** A fresh session per review target, the user's settled decisions marked as not open, and no reasoning or expected answer in the prompt.
- **Pin everything on every call.** Anything omitted falls back to `~/.codex/config.toml`, which may set `workspace-write` or low effort. `resume` keeps the conversation but not the settings.
- **stdin.** Claude Code gives a command a never-closing stdin when its text contains any `<`, so an unredirected `codex exec` hangs forever. Every call gets `- < prompt.md`, a pipe, or `</dev/null`. `resume` drops piped data unless the prompt is `-`.
- **Exit status.** Codex is the last command, unpiped. `| tee`, `| tail` or `; echo` hide failures.
- **Waiting.** Run in the background from the main conversation, not a subagent. Raise the 30-minute background timeout for long runs. Wait for the notification, and stop runs with TaskStop.

The failure table in `SKILL.md` comes from about 680 past `codex exec` runs and from experiments against codex-cli 0.160.0.

## Install

```bash
ln -s "$PWD" ~/.claude/skills/codex-peer
```

`agents/openai.yaml` disables implicit invocation, so when this directory is shared with Codex, Codex runs the skill only on an explicit `$codex-peer`.

## Test

```bash
./test_skill.sh          # static: command rules, flags and models against the installed CLI
./test_skill.sh --live   # also runs SKILL.md's own commands on a cheap model (uses Codex quota)
```

Run `--live` in the background. It takes a minute or two.
