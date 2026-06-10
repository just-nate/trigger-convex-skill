# Trigger.dev + Convex Skill

A clean, reusable agent skill for building **Trigger.dev v4 + Convex** integrations.

Use it for:

- durable background jobs
- Convex realtime state
- secure Trigger.dev → Convex HTTP callbacks
- queues and retries
- idempotent worker updates
- progress/activity timelines

## Install with the Skills CLI

```bash
npx skills add just-nate/trigger-convex-skill
```

Or install the specific skill path:

```bash
npx skills add https://github.com/just-nate/trigger-convex-skill/tree/main/skills/trigger-convex
```

## Install with `skills.sh`

```bash
curl -fsSL https://raw.githubusercontent.com/just-nate/trigger-convex-skill/main/skills.sh | bash
```

Custom skills directory:

```bash
SKILLS_DIR="$HOME/.claude/skills" bash skills.sh
```

Default install path:

```text
~/.agents/skills/trigger-convex
```

## Repo structure

```text
skills/trigger-convex/SKILL.md
skills.sh
README.md
LICENSE
```

## Scope

This skill is generic. It does not assume a specific app, framework, AI provider, storage provider, auth provider, billing system, or deployment platform.

## License

MIT
