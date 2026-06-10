# Trigger.dev + Convex Skill

A reusable agent skill for building production-grade **Trigger.dev v4 + Convex** integrations.

Use it when you need:

- durable background jobs
- Convex realtime state
- secure Trigger.dev → Convex HTTP callbacks
- queues and concurrency limits
- retries and idempotency
- progress/activity tracking
- worker-to-database synchronization

ELI5: Trigger.dev does the slow background work. Convex stores the live state. This skill teaches agents how to connect them safely.

## Install with the Skills CLI

```bash
npx skills add just-nate/trigger-convex-skill
```

Or install the specific skill path:

```bash
npx skills add https://github.com/just-nate/trigger-convex-skill/tree/main/skills/trigger-convex
```

## Install with `skills.sh`

This repo also includes a small installer script for people who want a direct shell setup.

```bash
curl -fsSL https://raw.githubusercontent.com/just-nate/trigger-convex-skill/main/skills.sh | bash
```

By default, it installs to:

```text
~/.agents/skills/trigger-convex
```

To install somewhere else:

```bash
SKILLS_DIR="$HOME/.claude/skills" bash skills.sh
```

## Manual install

Copy this folder into your agent skills directory:

```text
skills/trigger-convex
```

The installed result should look like:

```text
<your-skills-dir>/trigger-convex/SKILL.md
```

## What the skill covers

- Trigger.dev setup and `trigger.config.ts`
- Trigger.dev task patterns
- parent/child task orchestration
- `batchTriggerAndWait()` safety rules
- queues and concurrency
- retries and `AbortTaskRunError`
- secure Convex HTTP actions
- Convex validators, schema, and indexes
- idempotent internal mutations
- realtime UI query patterns
- verification checklist

## Scope

This skill is intentionally generic. It does **not** assume a specific product, AI provider, storage provider, auth provider, framework, or deployment platform.

## License

MIT
