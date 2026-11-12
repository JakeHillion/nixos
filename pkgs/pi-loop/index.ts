import { fileURLToPath } from "node:url";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const DYNAMIC_FALLBACK_MS = 60_000;
const MAX_TIMEOUT_MS = 2_147_483_647;

export default function (pi: ExtensionAPI) {
  type Job = {
    id: string;
    prompt: string;
    mode: "dynamic" | "interval" | "once";
    interval?: number;
    due: number;
  };
  const jobs = new Map<string, Job>();
  let nextId = 0;
  let ctx: ExtensionContext | undefined;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const result = (text: string) => ({ content: [{ type: "text" as const, text }], details: undefined });
  const list = () => Array.from(jobs.values(), (job) =>
    `${job.id}: ${job.mode}, ${new Date(job.due).toISOString()} — ${job.prompt}`,
  ).join("\n") || "No scheduled prompts.";

  function requirePersistent(context: ExtensionContext) {
    if (context.mode === "print" || context.mode === "json") {
      throw new Error("Scheduled prompts require a persistent interactive or RPC session.");
    }
  }
  function milliseconds(seconds: number) {
    const delay = seconds * 1000;
    if (!Number.isFinite(delay) || seconds < 1 || Number.isNaN(new Date(Date.now() + delay).getTime())) {
      throw new Error("Delay/interval must be at least one second and within the supported date range.");
    }
    return delay;
  }
  function nextJob() {
    let next: Job | undefined;
    for (const job of jobs.values()) {
      if (!next || job.due < next.due) next = job;
    }
    return next;
  }
  function arm(minimumDelay = 0) {
    if (timer !== undefined) clearTimeout(timer);
    timer = undefined;
    const next = nextJob();
    if (!ctx || !next) return;
    timer = setTimeout(tick, Math.min(MAX_TIMEOUT_MS, Math.max(minimumDelay, next.due - Date.now(), 0)));
    timer.unref();
  }
  function start(prompt: string, seconds?: number, once = false) {
    if (!prompt.trim()) throw new Error("A prompt is required.");
    const delay = seconds === undefined ? undefined : milliseconds(seconds);
    const job: Job = {
      id: String(++nextId), prompt,
      mode: once ? "once" : seconds === undefined ? "dynamic" : "interval",
      interval: once ? undefined : delay,
      due: Date.now() + (once ? delay! : 0),
    };
    jobs.set(job.id, job);
    arm();
    return job;
  }
  function cancel(id: string) {
    if (id === "all") jobs.clear();
    else if (!jobs.delete(id)) throw new Error(`Unknown schedule: ${id}`);
    arm();
  }
  function tick() {
    timer = undefined;
    if (!ctx) return;
    if (!ctx.isIdle() || ctx.hasPendingMessages()) {
      // agent_settled resumes promptly. A bounded retry also covers cancelled
      // branch summaries/manual compaction, which need not emit that event.
      arm(1000);
      return;
    }
    const job = nextJob();
    if (!job || job.due > Date.now()) {
      arm();
      return;
    }
    // Set the fallback before delivery: aborts, errors or a missing rearm must
    // not leave an apparently active dynamic loop with no next wake-up.
    job.due = Date.now() + (job.interval ?? DYNAMIC_FALLBACK_MS);
    if (job.mode === "once") jobs.delete(job.id);
    arm();
    // Pi splits /skill:name at the first literal space, not at a newline.
    const instruction = job.mode === "dynamic"
      ? ` \n\n[Dynamic loop ${job.id}: use schedule_wakeup with loopId "${job.id}" to choose the next delay, replacing the default 60-second fallback. Cancel with loop action=cancel id=${job.id}.]`
      : "";
    pi.sendUserMessage(job.prompt + instruction, { deliverAs: "followUp", expandPromptTemplates: true });
  }
  function clear() {
    if (timer !== undefined) clearTimeout(timer);
    timer = undefined;
    jobs.clear();
  }
  function stop() {
    clear();
    ctx = undefined;
  }
  pi.on("session_start", (_event, context) => {
    stop();
    ctx = context;
  });
  pi.on("session_shutdown", stop);
  pi.on("session_tree", (_event, context) => {
    clear();
    ctx = context;
  });
  pi.on("agent_settled", () => { arm(); });
  pi.on("resources_discover", () => ({
    skillPaths: [fileURLToPath(new URL("./skills/loop/SKILL.md", import.meta.url))],
  }));

  pi.registerTool({
    name: "loop",
    label: "Scheduled prompts",
    description: "Start, list or cancel session-local prompt loops. Omit intervalSeconds for self-paced ticks using schedule_wakeup, with a 60-second fallback if not rearmed; set it for a fixed interval. The first tick runs when idle. Starting loops requires a persistent interactive or RPC session. Schedules survive compaction, not session changes or process restarts.",
    parameters: Type.Object({
      action: Type.Union([Type.Literal("start"), Type.Literal("list"), Type.Literal("cancel")]),
      prompt: Type.Optional(Type.String()),
      intervalSeconds: Type.Optional(Type.Number({ minimum: 1 })),
      id: Type.Optional(Type.String({ description: "Schedule ID to cancel, or all." })),
    }),
    async execute(_callId, args, _signal, _onUpdate, context) {
      if (args.action === "start") {
        requirePersistent(context);
        const job = start(args.prompt ?? "", args.intervalSeconds);
        return result(`Loop ${job.id} started. It will run when this turn finishes. ${job.mode === "dynamic" ? "Choose each subsequent delay with schedule_wakeup and this loopId; otherwise it retries after 60 seconds." : "Missed ticks coalesce rather than accumulating."}`);
      }
      if (args.action === "cancel") cancel(args.id ?? "");
      return result(list());
    },
  });
  pi.registerTool({
    name: "schedule_wakeup",
    label: "Schedule wake-up",
    description: "Rearm a dynamic loop, replacing its pending timer, or schedule a one-off prompt. Pass loopId for a loop; otherwise provide prompt. A background completion can wake the session before a fallback timer fires. All prompts wait until the session is idle. Requires a persistent interactive or RPC session.",
    parameters: Type.Object({
      delaySeconds: Type.Number({ minimum: 1, maximum: 86400 }),
      loopId: Type.Optional(Type.String()),
      prompt: Type.Optional(Type.String()),
      reason: Type.Optional(Type.String()),
    }),
    async execute(_callId, args, _signal, _onUpdate, context) {
      requirePersistent(context);
      const delay = milliseconds(args.delaySeconds);
      if (args.loopId) {
        const job = jobs.get(args.loopId);
        if (!job || job.mode !== "dynamic") throw new Error("No such dynamic loop (it may have been cancelled).");
        job.due = Date.now() + delay;
        arm();
        return result(`Loop ${job.id} wakes at ${new Date(job.due).toISOString()}. ${args.reason ?? ""}`);
      }
      const job = start(args.prompt ?? "", args.delaySeconds, true);
      return result(`One-off prompt ${job.id} scheduled. Cancel with loop action=cancel id=${job.id}.`);
    },
  });
  pi.registerCommand("loop", {
    description: "/loop [5m|1h|…] <prompt>, /loop list, or /loop cancel <id|all>. Durations use whole numbers and s/m/h/d; no interval means self-paced.",
    async handler(args, context) {
      const input = args.trim();
      if (!input || input === "list") {
        context.ui.notify(list(), "info");
        return;
      }
      const [first, ...rest] = input.split(/\s+/);
      if (first === "cancel") {
        if (rest.length !== 1) throw new Error("Usage: /loop cancel <id|all>");
        cancel(rest[0]);
        context.ui.notify(list(), "info");
        return;
      }
      requirePersistent(context);
      const match = first.match(/^(\d+)([smhd])$/);
      if (!match && /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)[a-z]+$/i.test(first)) {
        throw new Error("Use a whole-number duration with s, m, h or d, followed by a prompt (for example: /loop 5m review changes).");
      }
      const units: Record<string, number> = { s: 1, m: 60, h: 3600, d: 86400 };
      const job = match ? start(input.slice(first.length).trim(), Number(match[1]) * units[match[2]]) : start(input);
      context.ui.notify(`Loop ${job.id} started (${job.mode}). Cancel: /loop cancel ${job.id}`, "info");
    },
  });
}
