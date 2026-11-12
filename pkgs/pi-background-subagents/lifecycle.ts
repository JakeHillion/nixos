import { execFileSync, type ChildProcess } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";

// Each Pi child starts in its own process group. Its bash tools may start more
// groups, so killing only the Pi PID (or only its group) is not sufficient.
export async function terminateTree(proc: ChildProcess): Promise<void> {
  if (!proc.pid) return;
  const groups = new Set([proc.pid]);

  function refresh() {
    const rows = execFileSync("@ps@", ["-axo", "pid=,ppid=,pgid=,stat="], { encoding: "utf8" })
      .trim().split("\n").filter(Boolean).map((line) => {
        const [pid, parent, group, state] = line.trim().split(/\s+/);
        return { pid: Number(pid), parent: Number(parent), group: Number(group), state };
      });
    const owned = new Set(rows.filter((row) => groups.has(row.group)).map((row) => row.pid));
    let size: number;
    do {
      size = owned.size;
      for (const row of rows) {
        if (groups.has(row.group) || owned.has(row.parent)) owned.add(row.pid);
        if (owned.has(row.pid)) groups.add(row.group);
      }
    } while (owned.size !== size);
    return rows.some((row) => groups.has(row.group) && !row.state.startsWith("Z"));
  }

  function signal(name: NodeJS.Signals) {
    for (const group of groups) {
      try {
        process.kill(-group, name);
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "ESRCH") throw error;
      }
    }
  }

  refresh();
  signal("SIGTERM");
  const deadline = Date.now() + 5000;
  while (refresh()) {
    if (Date.now() >= deadline) signal("SIGKILL");
    await delay(100);
  }
}
