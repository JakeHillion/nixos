export type HookResult =
  | { action: "allow" }
  | { action: "modify"; command: string }
  | { action: "block"; reason: string };
