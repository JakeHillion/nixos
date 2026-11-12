import { spawn, type ChildProcess } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/** Mirror main-chat text, not the TUI, reasoning, or tool transcripts. */
export default function (pi: ExtensionAPI) {
  let logger: { process: ChildProcess; closed: Promise<void> } | undefined;

  const stop = async () => {
    const current = logger;
    logger = undefined;
    if (!current) return;
    current.process.stdin?.end();
    const timeout = setTimeout(() => current.process.kill("SIGKILL"), 2000).unref();
    try {
      await current.closed;
    } finally {
      clearTimeout(timeout);
    }
  };

  pi.on("session_start", async (_event, ctx) => {
    await stop();
    // Workers inherit this profile, but their print/JSON conversations aren't
    // the main chat. Keep their output out of the journal.
    if (ctx.mode === "print" || ctx.mode === "json") return;

    const child = spawn(
      "@systemd-cat@",
      ["--identifier=ogygia-nix-fixer", "--level-prefix=false"],
      { stdio: ["pipe", "ignore", "inherit"] },
    );
    logger = {
      process: child,
      closed: new Promise<void>((resolve) => child.once("close", () => resolve())),
    };
    let reported = false;
    const failed = (reason: Error) => {
      if (logger?.process !== child || reported) return;
      reported = true;
      ctx.ui.notify(`Chat journaling failed: ${reason.message}`, "warning");
    };
    child.on("error", failed);
    child.stdin.on("error", failed);
    child.on("close", (code, signal) => {
      failed(new Error(`journal writer exited (${signal ?? code})`));
      if (logger?.process === child) logger = undefined;
    });
  });

  pi.on("message_end", ({ message }) => {
    if (!logger?.process.stdin?.writable) return;
    if (
      message.role !== "user" &&
      message.role !== "assistant" &&
      !(message.role === "custom" && message.display)
    ) return;

    let text = typeof message.content === "string"
      ? message.content
      : message.content.filter((part) => part.type === "text").map((part) => part.text).join("\n");
    if (message.role === "assistant" && message.stopReason === "error" &&
        !message.content.some((part) => part.type === "toolCall")) {
      text = [text, `Error: ${message.errorMessage || "Unknown error"}`].filter(Boolean).join("\n");
    }
    if (!text.trim()) return;
    const role = message.role === "custom" ? "notice" : message.role;
    logger.process.stdin.write(
      text.split(/\r?\n/).map((line) => `[${role}] ${line}`).join("\n") + "\n",
    );
  });

  pi.on("session_shutdown", stop);
}
