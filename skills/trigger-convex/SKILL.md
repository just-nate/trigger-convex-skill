---
name: trigger-convex
description: Build production-grade Trigger.dev v4 + Convex integrations. Use for durable background jobs, Convex realtime state, secure HTTP callbacks, queues, retries, idempotent mutations, progress timelines, and worker-to-database synchronization.
---

# Trigger.dev + Convex

Use this skill when a project needs **Trigger.dev v4** and **Convex** working together.

ELI5: Trigger.dev is the reliable worker that keeps trying slow jobs. Convex is the live notebook the app watches. Trigger.dev does the work, then tells Convex what happened so the UI updates in real time.

## Check current docs first

When network access is available, verify against the current provider docs before implementing:

- Trigger.dev manual setup: https://trigger.dev/docs/manual-setup
- Trigger.dev tasks: https://trigger.dev/docs/tasks/overview
- Trigger.dev triggering: https://trigger.dev/docs/triggering
- Trigger.dev queues/concurrency: https://trigger.dev/docs/queue-concurrency
- Trigger.dev errors/retrying: https://trigger.dev/docs/errors-retrying
- Trigger.dev idempotency: https://trigger.dev/docs/idempotency
- Convex HTTP actions: https://docs.convex.dev/functions/http-actions
- Convex validation: https://docs.convex.dev/functions/validation
- Convex actions: https://docs.convex.dev/functions/actions
- Convex internal functions: https://docs.convex.dev/functions/internal-functions
- Convex schemas/indexes: https://docs.convex.dev/database/schemas

If the repo has `convex/_generated/ai/guidelines.md`, read it before editing Convex code.

For copyable snippets and a short troubleshooting checklist, read `references/implementation-notes.md`.

## When to use

Use this skill for:

- durable jobs with realtime Convex UI state
- Trigger.dev workers that update Convex
- secure Trigger.dev → Convex HTTP callbacks
- progress timelines/activity feeds
- queues, retries, and idempotent worker writes
- parent/child task fan-out

Do not use this skill for:

- product-specific provider, storage, or business logic
- Convex-only auth/migrations/performance tasks
- Trigger.dev-only work with no Convex integration
- simple fast writes that fit inside a normal Convex mutation

## Recommended architecture

```text
Client or app backend
  -> Convex mutation records user intent and initial state
  -> Trigger.dev task starts durable work
  -> Trigger.dev posts progress/results to a secure Convex HTTP action
  -> Convex HTTP action validates auth and body
  -> Convex internal mutation applies an idempotent update
  -> Convex queries stream realtime state to the UI
```

Use Trigger.dev for long-running work, retries, queues, concurrency, fan-out, and worker observability.

Use Convex for realtime state, user-facing reads/writes, job/result/activity records, and secure callback ingestion.

Do **not** run long external work inside Convex queries or mutations.

## Trigger.dev rules

- Install `@trigger.dev/sdk`; install `@trigger.dev/build` and `trigger.dev` for local/deploy tooling.
- Keep Trigger.dev CLI, SDK, and build versions aligned.
- Define `trigger.config.ts` with `defineConfig` from `@trigger.dev/sdk`.
- Export tasks from directories listed in `dirs`.
- Use `task()` or `schemaTask()` from `@trigger.dev/sdk`.
- Use `tasks.trigger()` from backend code when triggering by task ID.
- Use task-instance `.trigger()`, `.triggerAndWait()`, and `.batchTriggerAndWait()` from inside tasks.
- Never wrap `triggerAndWait()` or Trigger wait calls in `Promise.all()`; use `batchTriggerAndWait()` for fan-out.
- Always check `result.ok` before reading `result.output`.
- Child tasks do not inherit parent queues; define queues explicitly.
- Use `idempotencyKey` when parent retries could trigger duplicate child tasks.
- Use `AbortTaskRunError` for failures that should not retry.
- Keep task payloads and outputs small and JSON serializable.

## Convex rules

- Define schemas in `convex/schema.ts` with `defineSchema` and `defineTable`.
- Use validators for args and return values when supported.
- Use internal functions for worker-owned writes.
- Define HTTP routes in `convex/http.ts` with `httpRouter()` and `httpAction()`.
- Manually validate HTTP request bodies; HTTP actions do not have Convex argument validators.
- Use `ctx.runMutation(internal.module.functionName, args)` from HTTP actions.
- Do not use `ctx.db` inside Convex actions.
- Use indexes with `withIndex()` for filtered reads.
- Avoid database `.filter()` for scalable queries.
- Avoid unbounded `.collect()`; use `.take(n)` or pagination.
- Use table-name DB APIs, such as `ctx.db.get("jobs", jobId)`.

## Minimal setup

Install packages with the project’s package manager.

```bash
bun add @trigger.dev/sdk zod
bun add -d @trigger.dev/build trigger.dev
```

Server-only env vars:

```bash
TRIGGER_SECRET_KEY=tr_dev_or_prod_...
CONVEX_SITE_URL=https://<deployment>.convex.site
CONVEX_WORKER_SECRET=long-random-shared-secret
```

Basic `trigger.config.ts`:

```ts
import { defineConfig } from "@trigger.dev/sdk";

export default defineConfig({
  project: "<trigger-project-ref>",
  dirs: ["./trigger"],
  retries: {
    enabledInDev: false,
    default: {
      maxAttempts: 3,
      minTimeoutInMs: 1_000,
      maxTimeoutInMs: 10_000,
      factor: 2,
      randomize: true,
    },
  },
  maxDuration: 3_600,
});
```

Add `.trigger` to `.gitignore`.

## Security requirements

- Never expose `TRIGGER_SECRET_KEY` or `CONVEX_WORKER_SECRET` to the browser.
- Worker callback endpoints must require `Authorization: Bearer <CONVEX_WORKER_SECRET>`.
- Missing auth returns `401`; wrong auth returns `403`.
- Do not add permissive CORS to worker-only endpoints.
- Validate callback JSON shape before calling internal mutations.
- Make callback mutations idempotent.
- Keep user-facing authorization in public Convex queries/mutations.

## Idempotency requirements

Worker callbacks and parent tasks may retry. Design so repeated operations are safe.

- Use stable event IDs such as `job-started:${jobId}` or `item-completed:${itemId}`.
- Add an index like `by_job_and_event_key` for activity dedupe.
- Skip duplicate activity rows.
- Do not move terminal records (`completed`/`failed`) back to `running`.
- Treat repeated completion callbacks as success.
- Use Trigger.dev `idempotencyKey` for child triggers.

## Verification checklist

Run the project’s relevant checks before calling work complete:

```bash
bun run typecheck
bun run check
bun run build
```

If the project does not use Bun, run equivalent npm/pnpm/yarn scripts.

Also verify:

- Trigger config exists and `dirs` matches task location.
- Trigger tasks are exported.
- Trigger CLI/SDK/build versions are aligned.
- `batchTriggerAndWait()` results check `result.ok`.
- No `Promise.all()` wraps Trigger wait calls.
- Callback secrets are server-only.
- Convex HTTP callbacks reject missing/wrong auth.
- HTTP callback bodies are manually validated.
- Worker mutations are idempotent.
- Queries use indexes and bounded reads.
- UI has loading, empty, error, and progress states where relevant.

## Scope guard

Keep this skill focused on Trigger.dev + Convex only. Do not add product-specific providers, features, storage layers, auth systems, billing flows, or deployment platforms unless the user explicitly asks.
