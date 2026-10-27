#!/usr/bin/env bash
# Cria o esqueleto .swarm/ no repositório. Idempotente: nunca sobrescreve o que já existe.
#
#   init-swarm.sh [dir]
#
# O mapa (.swarm/map.md) NÃO é criado aqui: quem o escreve é o agente mapper.

set -eu

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="${1:-$PWD}"

cd "$dir"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  cd "$(git rev-parse --show-toplevel)"
fi

created=()

mkd() { [ -d "$1" ] || { mkdir -p "$1"; created+=("$1/"); }; }
put() { # put <origem> <destino>
  [ -e "$2" ] || { cp "$1" "$2"; created+=("$2"); }
}

mkd .swarm/specs
mkd .swarm/tasks
mkd .swarm/templates
mkd .swarm/map
mkd .swarm/references
put "$plugin_root/templates/references-readme.md" .swarm/references/README.md

put "$plugin_root/templates/spec.md" .swarm/templates/spec.md
put "$plugin_root/templates/task.md" .swarm/templates/task.md
put "$plugin_root/templates/swarm-readme.md" .swarm/README.md
put "$plugin_root/templates/config.md" .swarm/config.md
put "$plugin_root/templates/prices.example.json" .swarm/prices.example.json
mkd .swarm/telemetry
[ -e .swarm/.gitignore ] || { printf 'telemetry/\nprices.json\n' > .swarm/.gitignore; created+=(".swarm/.gitignore"); }
put "$plugin_root/templates/designs.md" .swarm/designs.md

for d in specs tasks map; do
  [ -e ".swarm/$d/.gitkeep" ] || [ -n "$(ls -A ".swarm/$d" 2>/dev/null)" ] || { : > ".swarm/$d/.gitkeep"; }
done

if [ "${#created[@]}" -eq 0 ]; then
  echo "swarm: .swarm/ já estava completo em $PWD"
else
  echo "swarm: criado em $PWD:"
  printf '  %s\n' "${created[@]}"
fi
