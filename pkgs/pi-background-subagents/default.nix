{ runCommand, unstable, patch, procps, stdenv }:

runCommand "pi-background-subagents" { nativeBuildInputs = [ patch ]; } ''
  mkdir -p "$out"
  cp ${unstable.pi-coding-agent}/lib/node_modules/pi-monorepo/examples/extensions/subagent/{index,agents}.ts "$out/"
  chmod u+w "$out/index.ts"
  mv "$out/index.ts" "$out/upstream.ts"
  patch --fuzz=0 "$out/upstream.ts" < ${./upstream.patch}
  cp ${./index.ts} "$out/index.ts"
  cp ${./lifecycle.ts} "$out/lifecycle.ts"
  substituteInPlace "$out/lifecycle.ts" \
    --replace-fail '@ps@' '${if stdenv.hostPlatform.isDarwin then "/bin/ps" else "${procps}/bin/ps"}'
''
