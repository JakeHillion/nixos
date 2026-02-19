export type HookResult =
  | { action: "allow" }
  | { action: "modify"; command: string }
  | { action: "approve" }
  | { action: "approve_modify"; command: string }
  | { action: "block"; reason: string };
