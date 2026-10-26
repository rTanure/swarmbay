#!/usr/bin/env bash
# Verificações mecânicas de uma tarefa do swarm, sem gastar tokens de agente.
# Substitui o spec-reviewer nas rodadas de re-revisão (ele só entra uma vez, para a matriz critério -> teste).
#
#   check-mechanical.sh --task .swarm/tasks/T-001-x.md [--tests-sha SHA] [--base SHA] [--suite "comando"]
#
#   --task       arquivo da tarefa (obrigatório): confere cabeçalho (etapa, estado) e "Próximo passo" preenchido
#   --tests-sha  commit da etapa de testes: os arquivos de teste desse commit não podem ter mudado até o HEAD
#   --base       commit anterior ao início da tarefa: todo commit até o HEAD deve ter o prefixo tipo(T-NNN):
#   --suite      comando da suíte completa (do .swarm/map.md): precisa passar; só o resumo e as falhas são mostrados
#
# Também confere que a árvore de trabalho está limpa (a etapa anterior foi comitada).
# Saída: uma linha por verificação (ok | FALHA | n/a | aviso). Código 0 = tudo certo; 1 = alguma FALHA; 4 = uso inválido.

set -u

task=""; tests_sha=""; base=""; suite=""
while [ $# -gt 0 ]; do
  case "$1" in
    --task)      task="${2:-}"; shift 2 ;;
    --tests-sha) tests_sha="${2:-}"; shift 2 ;;
    --base)      base="${2:-}"; shift 2 ;;
    --suite)     suite="${2:-}"; shift 2 ;;
    -h|--help)   sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "check: opção desconhecida: $1" >&2; exit 4 ;;
  esac
done
[ -n "$task" ] || { echo "check: --task é obrigatório" >&2; exit 4; }
[ -f "$task" ] || { echo "check: tarefa não encontrada: $task" >&2; exit 4; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "check: não é um repositório git" >&2; exit 4; }

fails=0
ok()   { echo "ok     $1"; }
bad()  { echo "FALHA  $1"; fails=$((fails + 1)); }
na()   { echo "n/a    $1"; }
warn() { echo "aviso  $1"; }

tid=$(basename "$task" | grep -oE '^T-[0-9]+')

# 1. arquivo da tarefa
etapa=$(sed -n 's/^etapa:[[:space:]]*//p' "$task" | head -n1 | sed 's/[[:space:]]*#.*//')
estado=$(sed -n 's/^estado:[[:space:]]*//p' "$task" | head -n1 | sed 's/[[:space:]]*#.*//')
if [ -n "$etapa" ] && [ -n "$estado" ]; then ok "tarefa: etapa=$etapa estado=$estado"; else bad "tarefa: cabeçalho sem etapa/estado"; fi

next=$(awk '/^## Próximo passo/{f=1; next} /^## /{f=0} f && NF {print}' "$task")
if [ -n "$next" ] && printf '%s\n' "$next" | grep -qv '^('; then
  ok "tarefa: 'Próximo passo' preenchido"
else
  bad "tarefa: 'Próximo passo' vazio ou ainda com o texto do modelo"
fi

# 2. testes intocados desde a etapa de testes
if [ -n "$tests_sha" ]; then
  if git cat-file -e "${tests_sha}^{commit}" 2>/dev/null; then
    mapfile -t tfiles < <(git diff-tree --no-commit-id --name-only -r "$tests_sha" | grep -v '^\.swarm/')
    if [ "${#tfiles[@]}" -eq 0 ]; then
      na "testes: o commit $tests_sha não tem arquivos fora de .swarm/"
    else
      mapfile -t changed < <(git diff --name-only "$tests_sha" HEAD -- "${tfiles[@]}")
      if [ "${#changed[@]}" -eq 0 ]; then ok "testes intocados desde $tests_sha (${#tfiles[@]} arquivos)"
      else bad "testes alterados depois da etapa de testes: ${changed[*]}"; fi
    fi
  else
    bad "testes: commit $tests_sha não existe"
  fi
else
  na "testes intocados (sem --tests-sha)"
fi

# 3. um commit por etapa, com o prefixo da tarefa
if [ -n "$base" ] && [ -n "$tid" ]; then
  if git cat-file -e "${base}^{commit}" 2>/dev/null; then
    badc=$(git log --format='%h %s' "$base"..HEAD | grep -vE "^[0-9a-f]+ [a-z]+\(${tid}\): " || true)
    total=$(git rev-list --count "$base"..HEAD)
    if [ -z "$badc" ]; then ok "commits: $total, todos com prefixo tipo($tid):"
    else bad "commits sem o prefixo tipo($tid): $(printf '%s' "$badc" | tr '\n' ';')"; fi
  else
    bad "commits: base $base não existe"
  fi
else
  na "commits por etapa (sem --base ou id T-NNN no nome da tarefa)"
fi

# 4. árvore limpa
dirty=$(git status --porcelain | head -n 5)
if [ -z "$dirty" ]; then ok "árvore de trabalho limpa"; else bad "árvore suja (etapa sem commit?): $(printf '%s' "$dirty" | tr '\n' ';')"; fi

# 5. suíte completa
if [ -n "$suite" ]; then
  log=$(mktemp "${TMPDIR:-/tmp}/swarm-suite.XXXXXX.log")
  if bash -c "$suite" >"$log" 2>&1; then
    ok "suíte completa verde"
  else
    bad "suíte falhou (últimas linhas abaixo)"
    tail -n 20 "$log" | sed 's/^/         | /'
  fi
  skipped=$(grep -ciE 'skipped|pending|todo' "$log" || true)
  [ "${skipped:-0}" -gt 0 ] && warn "a saída da suíte menciona skipped/pending/todo ($skipped linhas): conferir se há testes pulados"
  rm -f "$log"
else
  na "suíte completa (sem --suite)"
fi

if [ "$fails" -eq 0 ]; then echo "check: tudo certo"; exit 0; fi
echo "check: $fails falha(s)"
exit 1
