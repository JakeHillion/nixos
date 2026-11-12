{ runCommand }:

runCommand "pi-loop" { } ''
  mkdir -p "$out/skills/loop"
  cp ${./index.ts} "$out/index.ts"
  cp ${./skills/loop/SKILL.md} "$out/skills/loop/SKILL.md"
''
