# Implementation notes

This file gives short copyable patterns without turning the skill into a full starter app.

## Package setup

Use the package manager already used by the project.

```bash
# Bun
bun add @trigger.dev/sdk zod
bun add -d @trigger.dev/build trigger.dev

# npm
npm install @trigger.dev/sdk zod
npm install --save-dev @trigger.dev/build trigger.dev

# pnpm
pnpm add @trigger.dev/sdk zod
pnpm add -D @trigger.dev/build trigger.dev
```

## Minimal Convex schema pattern

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

## Secure Convex callback pattern

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

## Idempotent internal mutation pattern

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

    // ELI5: don't let old/retried callbacks move a finished job backward.
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

## Trigger task pattern

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

    // Do one durable unit of work here.

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

## Callback helper

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

## Quick troubleshooting

- No Trigger tasks found: check `trigger.config.ts` `dirs`, exported tasks, and restart `trigger dev`.
- Duplicate child runs: add Trigger.dev `idempotencyKey` to child triggers.
- Duplicate Convex activities: add `eventKey` and dedupe with `by_job_and_event_key`.
- Callback returns `401`: missing `Authorization` header.
- Callback returns `403`: wrong `CONVEX_WORKER_SECRET` or env mismatch.
- Convex route missing: confirm the route is in `convex/http.ts` and use `.convex.site`, not `.convex.cloud`.
- Slow Convex query: replace DB `.filter()` with `withIndex()` and bound reads with `.take(n)` or pagination.
