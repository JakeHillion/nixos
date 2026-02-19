import { githubFetchHook } from "../src/hooks/github-fetch.js";

function readStdin(): Promise<string> {
  return new Promise((resolve) => {
    let data = "";
    process.stdin.on("data", (chunk: Buffer) => (data += chunk.toString()));
    process.stdin.on("end", () => resolve(data));
  });
}

async function main() {
  const stdin = await readStdin();
  const input = JSON.parse(stdin);

  const url: string = input.tool_input.url;

  const result = githubFetchHook(url);
  if (result.action === "block") {
    process.stderr.write(result.reason);
    process.exit(2);
  }

  process.exit(0);
}

main().catch((err: Error) => {
  process.stderr.write(`Hook error: ${err.message}`);
  process.exit(1);
});
