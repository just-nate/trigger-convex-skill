---
name: trigger-convex
description: Build production-grade Trigger.dev v4 + Convex integrations. Use for durable background jobs, Convex realtime state, secure HTTP callbacks, queues, retries, idempotent mutations, progress timelines, and worker-to-database synchronization.
---

# Trigger.dev + Convex

Use this skill when a project needs **Trigger.dev** and **Convex** working together.

ELI5: Trigger.dev is the reliable worker that can keep trying hard jobs. Convex is the live database the app watches. Trigger.dev does the slow work, then tells Convex what happened so the UI updates instantly.

## Always check current docs first

When network access is available, verify against the latest docs before implementing:

- Trigger.dev manual setup: https://trigger.dev/docs/manual-setup
- Trigger.dev tasks: https://trigger.dev/docs/tasks/overview
- Trigger.dev triggering: https://trigger.dev/docs/triggering
- Trigger.dev queues/concurrency: https://trigger.dev/docs/queue-concurrency
- Convex HTTP actions: https://docs.convex.dev/functions/http-actions
- Convex validation: https://docs.convex.dev/functions/validation
- Convex actions: https://docs.convex.dev/functions/actions
- Convex best practices: https://docs.convex.dev/understanding/best-practices/

If the repo has `convex/_generated/ai/guidelines.md`, read it before editing Convex code.

## Core architecture

Default integration pattern:

```text
Client
  -> Convex mutation records user intent
  -> Trigger.dev task starts durable work
  -> Trigger.dev updates Convex through secure HTTP callbacks
  -> Convex internal mutations update database state idempotently
  -> Convex queries stream realtime state to the UI
```

Use Trigger.dev for:

- long-running jobs
- retries
- queues and concurrency limits
- background orchestration
- child-task fan-out
- worker observability

Use Convex for:

- realtime app state
- job records
- result records
- progress/activity records
- user-facing queries and mutations
- secure callback ingestion from workers

Do not run long external work inside Convex queries or mutations.

## Setup checklist

### 1. Install Trigger.dev

Use the project package manager.

```bash
bun add @trigger.dev/sdk
bun add -d @trigger.dev/build trigger.dev
```

If the project does not use Bun, use its existing package manager instead.

Keep Trigger.dev CLI, SDK, and build package versions aligned.

### 2. Environment variables

Server-only variables:

```bash
TRIGGER_SECRET_KEY=tr_dev_or_prod_...
CONVEX_SITE_URL=https://<deployment>.convex.site
CONVEX_WORKER_SECRET=long-random-shared-secret
```

Never expose `TRIGGER_SECRET_KEY` or `CONVEX_WORKER_SECRET` to the browser.

### 3. Trigger config

Create `trigger.config.ts`:

```ts
import { defineConfig } from "@trigger.dev/sdk"

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
})
```

Add `.trigger` to `.gitignore`.

### 4. Convex schema

Model job systems with separate tables:

- `jobs`
- `jobResults`
- `jobActivities`

Convex schema rules:

- Use explicit validators in `convex/schema.ts`.
- Use `v.union(v.literal(...))` for statuses and enums.
- Use `v.id("table")` for document references.
- Add indexes for every filtered query pattern.
- Name indexes descriptively, such as `by_job`, `by_job_and_status`, `by_job_and_created_at`.
- Avoid unbounded arrays inside one document.

Common status vocabulary:

```ts
type JobStatus = "queued" | "running" | "retrying" | "failed" | "completed"
```

## Convex rules

### Public mutations

Use public mutations to record user intent and create initial state.

Good public mutation responsibilities:

- validate arguments
- check auth/ownership when needed
- create job records
- create initial activity records
- return IDs needed by the caller

Do not call external APIs from Convex mutations.

### Queries

Queries should power realtime UI.

Rules:

- Use `withIndex()` for filtered reads.
- Avoid `.filter()` on database queries.
- Avoid unbounded `.collect()`.
- Use `.take(n)` or pagination for lists.
- Return safe user-facing data only.

### HTTP actions

Use Convex HTTP actions for Trigger.dev callbacks.

Security rules:

- Worker-only endpoints must require a shared secret.
- Return `401` when auth is missing.
- Return `403` when auth is invalid.
- Manually validate request bodies because HTTP actions do not have Convex argument validators.
- Do not add permissive CORS to worker-only endpoints.
- Call internal mutations for database writes.

Example auth helper:

```ts
function authorizeWorker(request: Request) {
  const expected = process.env.CONVEX_WORKER_SECRET
  const authorization = request.headers.get("authorization")

  if (!authorization) {
    return new Response("Missing worker authorization", { status: 401 })
  }

  if (!expected || authorization !== `Bearer ${expected}`) {
    return new Response("Invalid worker authorization", { status: 403 })
  }

  return null
}
```

### Internal mutations

Worker callback mutations must be idempotent.

ELI5: idempotent means doing the same update twice is safe. If Trigger.dev retries a callback, Convex should not create duplicate progress rows or corrupt completed jobs.

Idempotency checklist:

- Use stable callback/event IDs when possible.
- Skip duplicate activity rows.
- Do not move a completed job back to running.
- Patch only valid status transitions.
- Treat repeated completion callbacks as success, not corruption.

## Trigger.dev rules

### Tasks

Use `task()` or `schemaTask()` from `@trigger.dev/sdk`.

Rules:

- Use stable task IDs.
- Keep payloads small and JSON serializable.
- Use `schemaTask()` with Zod for complex external payloads.
- Use `maxDuration` for jobs that should not run forever.
- Use Trigger metadata/tags for dashboard observability.
- Keep Convex as the UI source of truth.

### Queues and concurrency

Use explicit queues for rate-limited or costly work.

```ts
import { queue } from "@trigger.dev/sdk"

export const workerQueue = queue({
  name: "background-worker",
  concurrencyLimit: 2,
})
```

Use `concurrencyKey` for per-user, per-org, or per-resource fairness.

### Parent/child tasks

Use parent tasks for orchestration and child tasks for individual work units.

Rules:

- Child tasks do not inherit parent queues.
- Define queues on child tasks explicitly.
- For fan-out, prefer `batchTriggerAndWait()`.
- Never use `Promise.all()` with `triggerAndWait()` or wait calls.
- Always check `result.ok` before reading `result.output`.

Example:

```ts
import { task } from "@trigger.dev/sdk"
import { workerQueue } from "./queues"

export const childTask = task({
  id: "child-task",
  queue: workerQueue,
  retry: { maxAttempts: 4 },
  run: async (payload: { jobId: string; itemId: string }) => {
    // ELI5: this callback tells Convex one item started, so the UI can update.
    await postConvexCallback("/worker/item-started", payload)

    // Do one durable unit of work here.

    await postConvexCallback("/worker/item-completed", payload)
    return { itemId: payload.itemId }
  },
})

export const parentTask = task({
  id: "parent-task",
  retry: { maxAttempts: 3 },
  run: async (payload: { jobId: string; itemIds: string[] }) => {
    await postConvexCallback("/worker/job-started", { jobId: payload.jobId })

    const results = await childTask.batchTriggerAndWait(
      payload.itemIds.map((itemId) => ({
        payload: { jobId: payload.jobId, itemId },
        options: { idempotencyKey: `${payload.jobId}-${itemId}` },
      }))
    )

    const failed = results.filter((result) => !result.ok)
    if (failed.length > 0) {
      await postConvexCallback("/worker/job-failed", { jobId: payload.jobId })
      throw new Error(`${failed.length} child tasks failed`)
    }

    await postConvexCallback("/worker/job-completed", { jobId: payload.jobId })
    return { jobId: payload.jobId }
  },
})
```

### Retries

Retry transient failures:

- network failures
- rate limits
- `429`
- `5xx`

Do not retry user-correctable failures unless the input changes.

Use `AbortTaskRunError` for failures that should stop retries.

## Callback helper pattern

Trigger.dev tasks should call Convex with the worker secret:

```ts
export async function postConvexCallback(path: string, body: unknown) {
  const siteUrl = process.env.CONVEX_SITE_URL
  const secret = process.env.CONVEX_WORKER_SECRET

  if (!siteUrl || !secret) {
    throw new Error("Missing Convex worker callback environment variables")
  }

  const response = await fetch(`${siteUrl}${path}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${secret}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  })

  if (!response.ok) {
    throw new Error(`Convex callback failed with ${response.status}`)
  }
}
```

## Verification checklist

Before calling work complete:

```bash
bun run typecheck
bun run check
bun run build
```

If the project does not use Bun, run the equivalent project scripts.

Also verify:

- Trigger config exists.
- Trigger task files are inside configured `dirs`.
- Tasks are exported.
- Callback secrets are server-only.
- Convex HTTP callbacks reject missing/wrong auth.
- HTTP callback bodies are manually validated.
- Worker mutations are idempotent.
- Queries use indexes and bounded reads.
- `batchTriggerAndWait()` results check `result.ok`.
- No `Promise.all()` wraps Trigger wait calls.
- UI has loading, empty, error, and progress states where relevant.

## Scope guard

Keep this skill focused on Trigger.dev + Convex only:

- durable jobs
- realtime state
- callbacks
- queues
- retries
- idempotency
- progress/activity tracking

Do not add product-specific assumptions such as image generation, R2, auth providers, billing, or AI providers unless the user explicitly asks.
