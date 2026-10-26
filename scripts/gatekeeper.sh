#!/usr/bin/env bash
# Porteiro do swarmbay: diagnostica o repositório atual. Somente leitura.
#
#   gatekeeper.sh [dir]          imprime pares chave=valor
#   gatekeeper.sh --hook [dir]   formato de hook SessionStart (JSON); silencioso se nada a dizer
#
# state: empty | unmapped | stale | mapped
#   empty    sem código (ou diretório vazio)
#   unmapped tem código mas não há .swarm/map.md  -> rodar o fluxo `map`
#   stale    mapa existe mas o repo andou >= SWARM_STALE_COMMITS commits desde o mapeamento
#   mapped   pronto para trabalhar

set -u

mode=print
if [ "${1:-}" = "--hook" ]; then mode=hook; shift; fi
dir="${1:-$PWD}"
stale_after="${SWARM_STALE_COMMITS:-50}"

cd "$dir" 2>/dev/null || { echo "state=error"; echo "error=diretorio inacessivel: $dir"; exit 0; }

git_repo=no
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_repo=yes
  cd "$(git rev-parse --show-toplevel)" || exit 0
fi
root="$PWD"

has_commits=no
head_sha=""
if [ "$git_repo" = yes ] && head_sha=$(git rev-parse --verify -q HEAD 2>/dev/null); then
  has_commits=yes
fi

list_files() {
  if [ "$git_repo" = yes ]; then
    git ls-files -co --exclude-standard
  else
    find . -type f \
      -not -path './.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' \
      -not -path '*/target/*' -not -path '*/dist/*' -not -path '*/build/*' \
      2>/dev/null | sed 's|^\./||'
  fi
}

code_ext='\.(py|js|jsx|mjs|cjs|ts|tsx|go|rs|java|kt|kts|rb|php|c|h|cc|cpp|hpp|cs|swift|scala|sh|bash|vue|svelte|dart|lua|ex|exs|clj|hs|sql|zig)$'
manifests='(^|/)(package\.json|pyproject\.toml|setup\.py|requirements\.txt|Cargo\.toml|go\.mod|pom\.xml|build\.gradle(\.kts)?|Gemfile|composer\.json|mix\.exs|pubspec\.yaml|CMakeLists\.txt|Makefile)$'

code_files=$(list_files | grep -v '^\.swarm/' | grep -Ec "$code_ext|$manifests")
code_files=${code_files:-0}
has_code=no
[ "$code_files" -gt 0 ] && has_code=yes

mapped=no
mapped_at=""
commits_since=""
if [ -f .swarm/map.md ]; then
  mapped=yes
  mapped_at=$(sed -n 's/^mapped_at_commit:[[:space:]]*//p' .swarm/map.md | head -n1 | tr -d '[:space:]')
  if [ -n "$mapped_at" ] && [ "$git_repo" = yes ] && git cat-file -e "${mapped_at}^{commit}" 2>/dev/null; then
    commits_since=$(git rev-list --count "${mapped_at}..HEAD" 2>/dev/null)
  fi
fi

swarm_dir=no
[ -d .swarm ] && swarm_dir=yes

cfg() { # cfg <chave>: valor de .swarm/config.md sem aspas nem comentário
  sed -n "s/^$1:[[:space:]]*//p" .swarm/config.md 2>/dev/null | head -n1 | sed 's/[[:space:]]*#.*//; s/["'"'"']//g; s/[[:space:]]*$//'
}
mobile_first=$(cfg mobile_first)
mobile_usability=$(cfg mobile_usability)
config_pending=no
if [ ! -f .swarm/config.md ] || [ -z "$mobile_first" ] || [ "$mobile_first" = "?" ]; then
  config_pending=yes
elif [ "$mobile_first" = no ] && { [ -z "$mobile_usability" ] || [ "$mobile_usability" = "?" ]; }; then
  config_pending=yes
fi

stack=""
if [ -f .swarm/map.md ]; then
  stack=$(sed -n 's/^stack:[[:space:]]*//p' .swarm/map.md | head -n1 | tr -d '[]"' | sed 's/[[:space:]]*#.*//; s/,[[:space:]]*/,/g; s/[[:space:]]*$//')
fi

references=0
if [ -d .swarm/references ]; then
  references=$(find .swarm/references -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.gif' \) 2>/dev/null | wc -l | tr -d ' ')
fi

dsval() { # dsval <chave>: valor do cabeçalho de .swarm/designs.md
  sed -n "s/^$1:[[:space:]]*//p" .swarm/designs.md 2>/dev/null | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//'
}
design_system=$(dsval design_system_estado)
design_system=${design_system:-none}

ecc=no
if grep -q '"ecc@' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json" 2>/dev/null; then
  ecc=yes
fi

dirty=0
if [ "$git_repo" = yes ]; then
  dirty=$(git status --porcelain 2>/dev/null | grep -vc ' \.swarm/')
fi

task_lines=""
tasks_open=0
if [ -d .swarm/tasks ]; then
  for f in .swarm/tasks/T-*.md; do
    [ -f "$f" ] || continue
    estado=$(sed -n 's/^estado:[[:space:]]*//p' "$f" | head -n1 | tr -d '[:space:]')
    etapa=$(sed -n 's/^etapa:[[:space:]]*//p' "$f" | head -n1 | tr -d '[:space:]')
    case "$estado" in
      concluida|"") continue ;;
    esac
    tasks_open=$((tasks_open + 1))
    task_lines="${task_lines}task=$(basename "$f" .md) etapa=${etapa:-?} estado=${estado}
"
  done
fi

if [ "$has_code" = no ]; then
  state=empty
elif [ "$mapped" = no ]; then
  state=unmapped
elif [ -n "$commits_since" ] && [ "$commits_since" -ge "$stale_after" ]; then
  state=stale
else
  state=mapped
fi

case "$state" in
  empty)    next="fluxo init (projeto novo)" ;;
  unmapped) next="fluxo map: rodar scripts/init-swarm.sh e acionar o mapper antes de qualquer outro trabalho" ;;
  stale)    next="oferecer refazer o mapa (fluxo map) antes de seguir" ;;
  *)        next="classificar o pedido" ;;
esac
[ "$git_repo" = no ] && next="$next; ATENÇÃO: não é repositório git (pedir autorização para git init)"

if [ "$mode" = print ]; then
  echo "state=$state"
  echo "next=$next"
  echo "root=$root"
  echo "git=$git_repo"
  echo "has_commits=$has_commits"
  echo "head=$head_sha"
  echo "code_files=$code_files"
  echo "swarm_dir=$swarm_dir"
  echo "mapped=$mapped"
  echo "mapped_at_commit=$mapped_at"
  echo "commits_since_map=$commits_since"
  echo "dirty_files=$dirty"
  echo "design_system=$design_system"
  echo "references=$references"
  echo "ecc=$ecc"
  echo "stack=$stack"
  echo "config_pending=$config_pending"
  echo "mobile_first=${mobile_first:-?}"
  echo "mobile_usability=${mobile_usability:-?}"
  echo "tasks_open=$tasks_open"
  [ -n "$task_lines" ] && printf '%s' "$task_lines"
  exit 0
fi

# --- modo hook (SessionStart) ---
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export SWARMBAY_ROOT=\"$plugin_root\"" >> "$CLAUDE_ENV_FILE" 2>/dev/null
fi

msg=""
case "$state" in
  unmapped) msg="swarmbay: este repositório tem código (${code_files} arquivos) mas não está mapeado (.swarm/map.md ausente). Antes de qualquer trabalho, sugira ao usuário rodar /swarm map." ;;
  stale)    msg="swarmbay: o mapa em .swarm/map.md está defasado (${commits_since} commits desde o mapeamento). Sugira /swarm map." ;;
esac
if [ "$ecc" = no ]; then
  msg="${msg:+$msg }swarmbay depende do plugin ECC, que não está instalado: avise o usuário para rodar /plugin marketplace add affaan-m/ECC e /plugin install ecc@ecc. Sem ele os revisores especializados por stack ficam indisponíveis."
fi
if [ "$config_pending" = yes ] && [ "$swarm_dir" = yes ]; then
  msg="${msg:+$msg }swarmbay: o perfil do projeto (.swarm/config.md) ainda não foi respondido. No início do primeiro /swarm, pergunte ao usuário se a aplicação é mobile first."
fi
if [ "$tasks_open" -gt 0 ]; then
  msg="${msg:+$msg }swarmbay: há ${tasks_open} tarefa(s) em aberto em .swarm/tasks; /swarm status lista, /swarm resume continua."
fi

[ -z "$msg" ] && exit 0
msg=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg"
exit 0
