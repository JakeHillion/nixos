import { randomUUID } from "node:crypto";
import { setImmediate as nextTurn } from "node:timers/promises";
import { Type, type TObject } from "typebox";
import { Text } from "@earendil-works/pi-tui";
import type { ExtensionAPI, ToolDefinition } from "@earendil-works/pi-coding-agent";
import upstream from "./upstream.ts";

type Job = {
  controller: AbortController;
  state: "preparing" | "running";
  done: Promise<unknown>;
};

export default function (pi: ExtensionAPI) {
  const jobs = new Map<string, Job>();
  let generation = 0;
  const listJobs = () =>
    [...jobs].map(([id, job]) => `${id}: ${job.state}`).join("\n") ||
    "No background subagents.";

  async function cancel(id: string) {
    const job = jobs.get(id);
    if (!job) throw new Error(`Unknown background subagent: ${id}`);
    job.controller.abort();
    await job.done;
  }

  async function stop() {
    generation++;
    for (const job of jobs.values()) job.controller.abort();
    await Promise.allSettled([...jobs.values()].map((job) => job.done));
    jobs.clear();
  }

  // New/resume/fork/reload already emit shutdown. Tree navigation stays in the
  // same runtime, so clean up after it succeeds, not in a cancellable hook.
  pi.on("session_shutdown", stop);
  pi.on("session_tree", stop);

  // Keep upstream discovery, model inheritance, dispatch and rendering.
  upstream({
    ...pi,
    registerTool(tool: ToolDefinition<TObject, any>) {
      pi.registerTool({
        ...tool,
        description:
          tool.description +
          " Set background=true in a persistent session to return a job ID immediately after approval; the result arrives as a follow-up. Use subagent_tasks to list or cancel jobs.",
        parameters: Type.Object({
          ...tool.parameters.properties,
          background: Type.Optional(Type.Boolean({ default: false })),
        }),
        async execute(toolCallId, params, signal, onUpdate, ctx) {
          const { background, ...args } = params;
          if (!background) return tool.execute(toolCallId, args, signal, onUpdate, ctx);
          if (ctx.mode === "print" || ctx.mode === "json") {
            throw new Error("Background subagents require a persistent session; use foreground delegation here.");
          }

          const id = randomUUID();
          const owner = generation;
          const controller = new AbortController();
          const job: Job = { controller, state: "preparing", done: Promise.resolve() };
          jobs.set(id, job);

          // Upstream signals just before its first spawn. Until then, approval
          // and validation are part of this tool call and remain interruptible.
          const started = new Promise<null>((resolve) => {
            controller.signal.addEventListener("pi-subagent-start", () => resolve(null), { once: true });
          });
          const abort = () => controller.abort();
          signal?.addEventListener("abort", abort, { once: true });
          if (signal?.aborted) abort();

          let failedToStop: unknown;
          const execution = tool.execute(toolCallId, args, controller.signal, undefined, ctx).catch((error) => {
            if (controller.signal.aborted && error?.name !== "AbortError") failedToStop = error;
            return {
              content: [{ type: "text" as const, text: String(error) }],
              details: undefined,
              isError: true,
            };
          });
          job.done = execution;
          let detached = false;
          try {
            const result = await Promise.race([started, execution]);
            if (result !== null) return result;

            detached = true;
            job.state = "running";
            job.done = execution.then(async (result) => {
              // Even an immediate spawn failure must follow its launch receipt.
              await nextTurn();
              const cancelled = controller.signal.aborted && !failedToStop;
              const state = failedToStop ? "could not be stopped; processes may still be running" :
                cancelled ? "cancelled" : result.isError ? "failed" : "completed";
              if (owner === generation) pi.sendMessage({
                customType: "background-subagent",
                content: [{ type: "text", text: `Background subagent ${id} ${state}.` }, ...result.content],
                display: true,
                details: { id, state, result: result.details },
              }, { triggerTurn: !cancelled, deliverAs: cancelled ? "nextTurn" : "followUp" });
              if (failedToStop) throw new Error(`Could not stop background subagent ${id}`, { cause: failedToStop });
            }).finally(() => jobs.delete(id));
            // Cleanup/delivery failures must not become unhandled rejections.
            void job.done.catch((error) => console.error("Background subagent cleanup/delivery failed:", error));
            return {
              content: [{ type: "text", text: `Background subagent ${id} started. Its result will arrive automatically. Do not poll or start another writer in the same working copy while it runs.` }],
              details: { background: true, id },
            };
          } finally {
            signal?.removeEventListener("abort", abort);
            if (!detached) jobs.delete(id);
          }
        },
        renderResult(result, options, theme, context) {
          const launch = result.details as { background?: boolean; id?: string } | undefined;
          if (launch?.background) return new Text(`Background subagent ${launch.id} started.`, 0, 0);
          return tool.renderResult!(result, options, theme, context);
        },
      });
    },
  } as ExtensionAPI);

  pi.registerTool({
    name: "subagent_tasks",
    label: "Background subagents",
    description: "List active background subagent jobs, or cancel one by ID and wait for its processes to exit.",
    parameters: Type.Object({ id: Type.Optional(Type.String({ description: "Cancel this job; omit to list jobs." })) }),
    async execute(_id, { id }) {
      if (id) await cancel(id);
      return { content: [{ type: "text", text: listJobs() }], details: undefined };
    },
  });

  pi.registerCommand("subagents", {
    description: "List background jobs, or /subagents cancel <id>",
    async handler(args, ctx) {
      const [action, id] = args.trim().split(/\s+/);
      if (action === "cancel" && id) await cancel(id);
      else if (action) throw new Error("Usage: /subagents [cancel <id>]");
      ctx.ui.notify(listJobs(), "info");
    },
  });
}
