---
name: trigger-convex
description: Build production-grade Trigger.dev v4 + Convex integrations. Use for durable background jobs, Convex realtime state, secure HTTP callbacks, queues, retries, idempotent mutations, progress timelines, and worker-to-database synchronization.
---

# Trigger.dev + Convex

Build durable background systems where **Trigger.dev v4** does the long-running work and **Convex** stores realtime app state.

ELI5: Trigger.dev is the reliable worker. Convex is the live notebook. Trigger does slow work, then safely writes updates to Convex so the UI changes in real time.

## Check Current Docs First

When network access is available, verify implementation details against the provider docs:

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
- Convex schemas: https://docs.convex.dev/database/schemas
- Convex indexes: https://docs.convex.dev/database/reading-data/indexes/

If the repo has `convex/_generated/ai/guidelines.md`, read it before editing Convex code. It overrides generic Convex memory.

## When To Use

Use this skill for:

- durable jobs with realtime Convex UI state
- Trigger.dev workers that update Convex
- secure Trigger.dev → Convex HTTP callbacks
- progress timelines and activity feeds
- queues, retries, and idempotent worker writes
- parent/child task fan-out

Do not use this skill for:

- product-specific provider or business logic
- Convex-only auth, migration, or performance tasks
- Trigger.dev-only work with no Convex integration
- simple fast writes that fit inside a normal Convex mutation

## Core Architecture

Use this default pattern:

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

Use Convex for realtime state, user-facing reads/writes, job records, result records, activity records, and secure callback ingestion.

Do **not** run long external work inside Convex queries or mutations.

## Setup

Install packages with the project's package manager.

```bash
bun add @trigger.dev/sdk zod
bun add -d @trigger.dev/build trigger.dev
```

Equivalent npm/pnpm/yarn commands are fine if the project does not use Bun.

Server-only environment variables:

```bash
TRIGGER_SECRET_KEY=tr_dev_or_prod_...
CONVEX_SITE_URL=https://<deployment>.convex.site
CONVEX_WORKER_SECRET=long-random-shared-secret
```

Never expose `TRIGGER_SECRET_KEY` or `CONVEX_WORKER_SECRET` to the browser.

Create `trigger.config.ts`:

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

## Trigger.dev Rules

- Use `@trigger.dev/sdk` v4 APIs.
- Keep Trigger.dev CLI, SDK, and build package versions aligned.
- Export tasks from files inside the configured `dirs` folder.
- Use `task()` or `schemaTask()`.
- Use `tasks.trigger()` from backend code when triggering by task ID.
- Use task instance `.trigger()`, `.triggerAndWait()`, and `.batchTriggerAndWait()` from inside tasks.
- Never wrap `triggerAndWait()` or Trigger wait calls in `Promise.all()`.
- Use `batchTriggerAndWait()` for fan-out.
- Always check `result.ok` before reading `result.output`.
- Child tasks do not inherit parent queues; define queues explicitly.
- Use `idempotencyKey` when parent retries could duplicate child task runs.
- Use `AbortTaskRunError` for failures that should not retry.
- Keep task payloads and outputs small and JSON serializable.

## Convex Rules

- Define schemas in `convex/schema.ts` with `defineSchema` and `defineTable`.
- Use validators for function args and return values when supported.
- Use `v.union(v.literal(...))` for statuses and enums.
- Add indexes for every filtered query pattern.
- Define HTTP routes in `convex/http.ts` with `httpRouter()` and `httpAction()`.
- Manually validate HTTP request bodies; HTTP actions do not have Convex argument validators.
- Use internal functions for worker-owned writes.
- Call worker writes from HTTP actions with `ctx.runMutation(internal.module.functionName, args)`.
- Do not use `ctx.db` inside Convex actions.
- Use `withIndex()` for filtered reads.
- Avoid database `.filter()` for scalable queries.
- Avoid unbounded `.collect()`; use `.take(n)` or pagination.
- Use table-name DB APIs, such as `ctx.db.get("jobs", jobId)`.

## Minimal Schema Pattern

```ts
import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

const jobStatus = v.union(
  v.literal("queued"),
  v.literal("running"),
  v.literal("retrying"),
  v.literal("failed"),
  v.literal("completed"),
);

export default defineSchema({
  jobs: defineTable({
    status: jobStatus,
    totalItems: v.number(),
    completedItems: v.number(),
    failedItems: v.number(),
    error: v.optional(v.string()),
  }).index("by_status", ["status"]),

  jobActivities: defineTable({
    jobId: v.id("jobs"),
    eventKey: v.string(),
    type: v.string(),
    message: v.string(),
    createdAt: v.number(),
  })
    .index("by_job_and_created_at", ["jobId", "createdAt"])
    .index("by_job_and_event_key", ["jobId", "eventKey"]),
});
```

## Secure Callback Pattern

Trigger.dev should call Convex through a worker-only HTTP action.

Security rules:

- Require `Authorization: Bearer <CONVEX_WORKER_SECRET>`.
- Return `401` when auth is missing.
- Return `403` when auth is wrong.
- Do not add permissive CORS to worker-only endpoints.
- Validate callback JSON before writing to the database.
- Call internal mutations for database writes.

```ts
import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { internal } from "./_generated/api";

const http = httpRouter();

http.route({
  path: "/worker/events",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const authError = authorizeWorker(request);
    if (authError) return authError;

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return new Response("Invalid JSON", { status: 400 });
    }

    const event = parseWorkerEvent(body);
    if (!event.ok) return new Response(event.error, { status: 400 });

    await ctx.runMutation(internal.jobs.applyWorkerEvent, event.value);
    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  }),
});

function authorizeWorker(request: Request) {
  const expected = process.env.CONVEX_WORKER_SECRET;
  const authorization = request.headers.get("authorization");

  if (!authorization) {
    return new Response("Missing worker authorization", { status: 401 });
  }

  if (!expected || authorization !== `Bearer ${expected}`) {
    return new Response("Invalid worker authorization", { status: 403 });
  }

  return null;
}

function parseWorkerEvent(value: unknown) {
  if (typeof value !== "object" || value === null) {
    return { ok: false as const, error: "Body must be an object" };
  }

  const body = value as Record<string, unknown>;
  if (typeof body.eventKey !== "string") {
    return { ok: false as const, error: "eventKey is required" };
  }
  if (typeof body.jobId !== "string") {
    return { ok: false as const, error: "jobId is required" };
  }
  if (typeof body.type !== "string") {
    return { ok: false as const, error: "type is required" };
  }
  if (typeof body.message !== "string") {
    return { ok: false as const, error: "message is required" };
  }

  return {
    ok: true as const,
    value: {
      eventKey: body.eventKey,
      jobId: body.jobId,
      type: body.type,
      message: body.message,
    },
  };
}

export default http;
```

## Idempotent Mutation Pattern

Worker callbacks may be retried. Mutations must be safe to run more than once.

ELI5: clicking the same elevator button twice should not create two elevators. A retried callback should not duplicate rows or move a finished job backward.

```ts
import { internalMutation } from "./_generated/server";
import { v } from "convex/values";

export const applyWorkerEvent = internalMutation({
  args: {
    eventKey: v.string(),
    jobId: v.id("jobs"),
    type: v.string(),
    message: v.string(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("jobActivities")
      .withIndex("by_job_and_event_key", (q) =>
        q.eq("jobId", args.jobId).eq("eventKey", args.eventKey),
      )
      .unique();

    if (existing) return null;

    const job = await ctx.db.get("jobs", args.jobId);
    if (!job) return null;

    await ctx.db.insert("jobActivities", {
      jobId: args.jobId,
      eventKey: args.eventKey,
      type: args.type,
      message: args.message,
      createdAt: Date.now(),
    });

    // ELI5: old retried callbacks should not move a finished job backward.
    if (job.status === "completed" || job.status === "failed") {
      return null;
    }

    if (args.type === "job_started") {
      await ctx.db.patch("jobs", args.jobId, { status: "running" });
    }

    if (args.type === "job_completed") {
      await ctx.db.patch("jobs", args.jobId, { status: "completed" });
    }

    if (args.type === "job_failed") {
      await ctx.db.patch("jobs", args.jobId, { status: "failed" });
    }

    return null;
  },
});
```

## Trigger Task Pattern

```ts
import { queue, schemaTask } from "@trigger.dev/sdk";
import { z } from "zod";

const workerQueue = queue({
  name: "background-worker",
  concurrencyLimit: 2,
});

export const childTask = schemaTask({
  id: "child-task",
  queue: workerQueue,
  schema: z.object({
    jobId: z.string(),
    itemId: z.string(),
  }),
  retry: { maxAttempts: 4 },
  run: async (payload) => {
    await postConvexWorkerEvent({
      eventKey: `item-started:${payload.itemId}`,
      type: "item_started",
      jobId: payload.jobId,
      message: "Item started",
    });

    // ELI5: do one durable unit of slow work here.

    await postConvexWorkerEvent({
      eventKey: `item-completed:${payload.itemId}`,
      type: "item_completed",
      jobId: payload.jobId,
      message: "Item completed",
    });

    return { itemId: payload.itemId };
  },
});

export const parentTask = schemaTask({
  id: "parent-task",
  schema: z.object({
    jobId: z.string(),
    itemIds: z.array(z.string()).min(1),
  }),
  retry: { maxAttempts: 3 },
  run: async (payload) => {
    await postConvexWorkerEvent({
      eventKey: `job-started:${payload.jobId}`,
      type: "job_started",
      jobId: payload.jobId,
      message: "Job started",
    });

    const results = await childTask.batchTriggerAndWait(
      payload.itemIds.map((itemId) => ({
        payload: { jobId: payload.jobId, itemId },
        options: { idempotencyKey: `${payload.jobId}:${itemId}` },
      })),
    );

    const failed = results.filter((result) => !result.ok);
    if (failed.length > 0) {
      await postConvexWorkerEvent({
        eventKey: `job-failed:${payload.jobId}`,
        type: "job_failed",
        jobId: payload.jobId,
        message: `${failed.length} item(s) failed`,
      });
      throw new Error(`${failed.length} child task(s) failed`);
    }

    await postConvexWorkerEvent({
      eventKey: `job-completed:${payload.jobId}`,
      type: "job_completed",
      jobId: payload.jobId,
      message: "Job completed",
    });

    return { jobId: payload.jobId };
  },
});
```

## Callback Helper

```ts
export async function postConvexWorkerEvent(body: unknown) {
  const siteUrl = process.env.CONVEX_SITE_URL;
  const secret = process.env.CONVEX_WORKER_SECRET;

  if (!siteUrl || !secret) {
    throw new Error("Missing Convex callback environment variables");
  }

  const response = await fetch(`${siteUrl}/worker/events`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${secret}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    throw new Error(`Convex callback failed with ${response.status}`);
  }
}
```

## Quick Troubleshooting

- No Trigger tasks found: check `trigger.config.ts` `dirs`, exported tasks, and restart `trigger dev`.
- Duplicate child runs: add Trigger.dev `idempotencyKey` to child triggers.
- Duplicate Convex activities: add `eventKey` and dedupe with `by_job_and_event_key`.
- Callback returns `401`: missing `Authorization` header.
- Callback returns `403`: wrong `CONVEX_WORKER_SECRET` or environment mismatch.
- Convex route missing: confirm the route is in `convex/http.ts` and use `.convex.site`, not `.convex.cloud`.
- Slow Convex query: replace database `.filter()` with `withIndex()` and bound reads with `.take(n)` or pagination.

## Verification Checklist

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
- Trigger CLI, SDK, and build versions are aligned.
- `batchTriggerAndWait()` results check `result.ok`.
- No `Promise.all()` wraps Trigger wait calls.
- Callback secrets are server-only.
- Convex HTTP callbacks reject missing/wrong auth.
- HTTP callback bodies are manually validated.
- Worker mutations are idempotent.
- Queries use indexes and bounded reads.
- UI has loading, empty, error, and progress states where relevant.

## Golden Rule

**Trigger.dev does durable work. Convex owns realtime truth. Connect them with secure, idempotent callbacks.**
