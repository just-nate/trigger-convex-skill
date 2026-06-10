# Trigger.dev + Convex Skill

A reusable agent skill for building clean **Trigger.dev v4 + Convex** integrations.

Use it when you want Trigger.dev to run durable background work and Convex to stay the realtime source of truth for your app.

```text
Trigger.dev = durable worker, retries, queues, orchestration
Convex      = realtime state, user-facing data, progress updates
```

## What this skill helps with

- Durable background jobs
- Secure Trigger.dev → Convex HTTP callbacks
- Convex realtime job state
- Progress and activity timelines
- Parent/child Trigger.dev task fan-out
- Queues, retries, and concurrency limits
- Idempotent Convex worker mutations
- Safe separation between worker code and user-facing app code

## Install

### Skills CLI

```bash
npx skills add just-nate/trigger-convex-skill
```

Install only this skill path:

```bash
npx skills add https://github.com/just-nate/trigger-convex-skill/tree/main/skills/trigger-convex
```

### Shell installer

```bash
curl -fsSL https://raw.githubusercontent.com/just-nate/trigger-convex-skill/main/skills.sh | bash
```

By default, this installs to:

```text
~/.agents/skills/trigger-convex
```

Use a custom skills directory:

```bash
SKILLS_DIR="$HOME/.claude/skills" bash skills.sh
```

### Manual install

Copy the skill folder into your agent skills directory:

```bash
mkdir -p ~/.agents/skills
cp -R skills/trigger-convex ~/.agents/skills/trigger-convex
```

## Example prompts

After installing, ask your agent things like:

```text
Use the trigger-convex skill to add durable background jobs with Convex realtime status.
```

```text
Design a secure Trigger.dev worker callback flow for Convex.
```

```text
Review this Trigger.dev + Convex job system for idempotency and security issues.
```

## What the skill teaches agents

The skill tells agents to follow this architecture:

```text
Client or app backend
  -> Convex mutation records user intent
  -> Trigger.dev task runs durable work
  -> Trigger.dev posts progress to Convex HTTP action
  -> Convex validates the callback
  -> Convex internal mutation updates state idempotently
  -> Convex queries stream realtime updates to the UI
```

It also points agents to the current provider docs for:

- Trigger.dev setup, tasks, triggering, queues, retries, and idempotency
- Convex HTTP actions, validation, internal functions, schemas, and indexes

## Repo structure

```text
.
├── LICENSE
├── README.md
├── skills.sh
└── skills/
    └── trigger-convex/
        └── SKILL.md
```

## Scope

This skill is intentionally generic.

It does **not** assume a specific:

- app framework
- product type
- AI provider
- storage provider
- auth provider
- billing system
- deployment platform

## Security posture

This skill emphasizes:

- server-only secrets
- authenticated worker callbacks
- manual HTTP body validation
- internal Convex mutations for worker-owned writes
- idempotent updates so retries are safe
- indexed, bounded Convex queries

## License

MIT
