---
name: loop
description: Run recurring prompts, choose each next wake-up dynamically, or schedule a one-off reminder
---

Use the `loop` tool to start, list, or cancel loops in an interactive or RPC
session, not a print/JSON subagent. Omit `intervalSeconds` for self-paced work.
The first tick runs after the current turn finishes. Each dynamic tick includes
its loop ID; call `schedule_wakeup` with that `loopId` and your chosen
`delaySeconds`. Reusing the ID replaces its previous timer rather than creating
another loop. Each dispatch retains a 60-second fallback, which runs when idle
if the turn aborts, fails, or omits rearming; explicitly cancel the loop to stop.

When waiting for a background agent, arm a fallback wake-up and yield.
Its completion wakes this same session. Check whether it is still running
before starting another writer, and rearm the same loop ID as appropriate.
Don't poll or block the interactive session with a long sleep.

For one-off reminders, call `schedule_wakeup` with a `prompt` and no loop ID.
To stop, cancel the schedule with the `loop` tool or `/loop cancel <id|all>`.
The `/loop` command accepts whole-number durations such as `5m` or `1h`, with
units `s`, `m`, `h`, or `d`, followed by a prompt. Scheduled skill commands and
prompt templates are expanded as normal.
Schedules wait until idle, survive compaction, and are cleared when leaving
or restarting the session. No schedules or lock files are written to the repo.
