# Codex Peer Skill

AI skill for using OpenAI Codex as an independent peer reviewer: safe read-only `codex exec`, resume loops, synthesis.

**This skill is deliberately conservative: read-only sandbox by default, `approval_policy="never"` pinned on every run, writes only as a separate explicitly authorized step, and the final recommendation always belongs to the calling agent, not to Codex.**

## Why this exists

Agents that shell out to the Codex CLI keep making the same mistakes. They leak their preferred conclusion into the prompt and get an echo instead of a review. They forget to close stdin on background runs and the process waits forever. They run with the ambient `workspace-write` sandbox and Codex edits files in the middle of a "review". They place flags after `resume` and get exit 2, accept the CLI's `full-auto` error tip and silently widen permissions, or present progress events from a failed run as Codex's conclusion.

The guidance here was distilled from about 200 real `codex exec` runs over four months of daily use across several codebases. Every gotcha traces to a real incident, and the test suite checks the documented flag contract against the installed CLI so drift gets caught.

### What agents get wrong vs. what this skill enforces

| Topic | What agents do (wrong) | What the skill enforces |
|-------|------------------------|-------------------------|
| Independence | "Confirm that option B is better" | Neutral prompt with facts, constraints, and open questions |
| Approval policy | Rely on ambient config | `-c 'approval_policy="never"'` on every run |
| Sandbox | Ambient `workspace-write`, Codex edits mid-review | `--sandbox read-only`; writes are a separate authorized step |
| Stdin | Prompt as argument, stdin left open, process hangs | `</dev/null` whenever the prompt is an argument |
| Large input | Interpolate file contents into the shell argument | Pipe through stdin |
| Resume | `--sandbox` after `resume` (exit 2), or ambiguous `resume --last` | Exec-level flags before `resume`, session ID from the run banner |
| Effort | Trust config defaults that pin low effort | Explicit model and reasoning effort per review |
| Flag errors | Accept the CLI tip suggesting `full-auto` | Never; it silently widens the sandbox |
| Failures | Present progress events as the review | Report the failed run separately from own analysis |

## Installation

### Claude Code

```bash
mkdir -p ~/.claude/skills/codex-peer
cp SKILL.md ~/.claude/skills/codex-peer/
```

The skill activates when you explicitly ask for a Codex second opinion ("ask codex", "/codex-peer", "get a Codex review of this plan"). It stays out of ordinary reviews that do not name Codex.

### Codex CLI

```bash
mkdir -p ~/.codex/skills/codex-peer
cp -r SKILL.md agents ~/.codex/skills/codex-peer/
```

Inside Codex the skill does not launch `codex exec` recursively; it routes the independent pass through native delegation.

### Other AI tools

`SKILL.md` is plain markdown and self-contained. Feed it as context to any shell-capable coding agent; the core workflow and CLI guidance are host-neutral, with Claude Code specifics isolated in one clearly marked section.

## File structure

```
SKILL.md            # Host gate, core workflow, safe CLI invocation, failure handling
agents/openai.yaml  # Codex-side skill metadata (explicit invocation only)
evals/evals.json    # 21 behavioral eval cases
test_skill.sh       # Deterministic drift tests; --live adds opt-in CLI smoke tests
```

## Testing

```bash
./test_skill.sh          # static checks, offline, free
./test_skill.sh --live   # opt-in smoke tests against the real CLI (consumes Codex usage)
```

The static suite pins the safety-critical guidance (approval override in every example, resume flag ordering, no personal paths or emails) and verifies every documented flag against `codex exec --help` when the CLI is installed.

## Contributing

Found a CLI behavior change, a new failure mode, or a mistake agents make with Codex? PRs welcome. Please include how it reproduces (CLI version and command shape) for any additions.
