#!/usr/bin/env bash
# Tira prints das telas da aplicação com Chrome/Chromium headless.
#
#   capture-screens.sh --base-url URL --routes "/,/login" [opções]
#
# Opções:
#   --base-url URL        base da aplicação (padrão: http://localhost:3000)
#   --routes LISTA        rotas separadas por vírgula (padrão: /)
#   --viewports LISTA     nome=LxA separados por vírgula (padrão: mobile=390x844,desktop=1440x900)
#   --out DIR             destino (padrão: .swarm/references/capturas)
#   --start CMD           comando que sobe a aplicação; é encerrado ao final
#   --timeout SEG         espera máxima pela aplicação no ar (padrão: 60)
#   --wait-ms MS          tempo para o JS renderizar antes do print (padrão: 3000)
#   --scale N             device scale factor (padrão: 1)
#   --allow-remote        permite URLs fora de localhost/file:// (por padrão, recusa)
#
# Variáveis: CHROME_BIN (caminho do navegador), CHROME_NO_SANDBOX=1 (necessário em alguns containers).
#
# Códigos de saída: 0 ok · 1 alguma captura falhou · 2 sem navegador · 3 aplicação não subiu · 4 uso/URL inválida
#                   5 nada capturado porque todas as rotas exigem login
#
# SÓ TELAS PÚBLICAS: o script não faz login e não aceita cookie, token ou sessão. Rota que responde 401/403 ou
# redireciona para uma página de login é PULADA (não conta como falha). Páginas que fazem o redirecionamento
# só no navegador (SPA) escapam dessa checagem: quem chama deve escolher só rotas públicas e conferir as imagens.
# Telas autenticadas: o usuário adiciona as imagens manualmente em .swarm/references/.
#
# Só escreve em --out (padrão .swarm/references/capturas) e só sobrescreve o PNG da própria captura;
# nunca apaga nem altera outros arquivos da pasta de referências.
#
# Captura só a área visível (a altura do viewport). Para telas longas, aumente a altura no viewport (ex.: desktop=1440x2400).
# As capturas podem mostrar dados reais: o usuário deve conferir antes de versionar.

set -u

base_url="http://localhost:3000"
routes="/"
viewports="mobile=390x844,desktop=1440x900"
out=".swarm/references/capturas"
start_cmd=""
timeout_s=60
wait_ms=3000
scale=1
allow_remote=no

while [ $# -gt 0 ]; do
  case "$1" in
    --base-url)     base_url="${2:-}"; shift 2 ;;
    --routes)       routes="${2:-}"; shift 2 ;;
    --viewports)    viewports="${2:-}"; shift 2 ;;
    --out)          out="${2:-}"; shift 2 ;;
    --start)        start_cmd="${2:-}"; shift 2 ;;
    --timeout)      timeout_s="${2:-}"; shift 2 ;;
    --wait-ms)      wait_ms="${2:-}"; shift 2 ;;
    --scale)        scale="${2:-}"; shift 2 ;;
    --allow-remote) allow_remote=yes; shift ;;
    -h|--help)      sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "capture: opção desconhecida: $1" >&2; exit 4 ;;
  esac
done

# --- só localhost por padrão ---
case "$base_url" in
  http://localhost*|http://127.0.0.1*|http://\[::1\]*|https://localhost*|https://127.0.0.1*|file://*) ;;
  *)
    if [ "$allow_remote" != yes ]; then
      echo "capture: recusado: $base_url não é local. Use --allow-remote se for intencional (cuidado com dados reais)." >&2
      exit 4
    fi ;;
esac

# --- navegador ---
chrome=""
if [ -n "${CHROME_BIN:-}" ]; then
  [ -x "$CHROME_BIN" ] && chrome="$CHROME_BIN"
else
  for b in google-chrome google-chrome-stable chromium chromium-browser chrome; do
    if command -v "$b" >/dev/null 2>&1; then chrome="$(command -v "$b")"; break; fi
  done
fi
if [ -z "$chrome" ]; then
  echo "capture: nenhum Chrome/Chromium encontrado (defina CHROME_BIN). Peça ao usuário as imagens de referência." >&2
  exit 2
fi

mkdir -p "$out" || { echo "capture: não consegui criar $out" >&2; exit 4; }

# --- sobe a aplicação, se pedido ---
app_pid=""
log=""
cleanup() {
  if [ -n "$app_pid" ]; then
    kill -- "-$app_pid" 2>/dev/null || kill "$app_pid" 2>/dev/null
    wait "$app_pid" 2>/dev/null
  fi
}
trap cleanup EXIT INT TERM

if [ -n "$start_cmd" ]; then
  log="$(mktemp "${TMPDIR:-/tmp}/swarm-app.XXXXXX.log")"
  setsid bash -c "$start_cmd" >"$log" 2>&1 &
  app_pid=$!
fi

case "$base_url" in
  file://*) ;;
  *)
    if ! command -v curl >/dev/null 2>&1; then
      echo "capture: curl é necessário para esperar a aplicação" >&2; exit 4
    fi
    up=no
    for _ in $(seq 1 "$timeout_s"); do
      code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$base_url" 2>/dev/null)
      if [ -n "$code" ] && [ "$code" != 000 ]; then up=yes; break; fi
      if [ -n "$app_pid" ] && ! kill -0 "$app_pid" 2>/dev/null; then break; fi
      sleep 1
    done
    if [ "$up" != yes ]; then
      echo "capture: a aplicação não respondeu em $base_url (${timeout_s}s)." >&2
      [ -n "$log" ] && { echo "--- últimas linhas do log:" >&2; tail -n 15 "$log" >&2; }
      exit 3
    fi ;;
esac

slug() { # rota -> nome de arquivo
  local s
  s=$(printf '%s' "$1" | sed 's|^/*||; s|[^A-Za-z0-9]\{1,\}|-|g; s|^-||; s|-$||')
  printf '%s' "${s:-home}"
}

mobile_ua='Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'

sandbox=""
[ "${CHROME_NO_SANDBOX:-}" = 1 ] && sandbox="--no-sandbox"

login_re='/(log-?in|sign-?in|signin|auth|sso|entrar|acessar)([/?#]|$)'

# público? 0 = sim · 1 = exige login · 2 = não encontrada (404) · 3 = erro de servidor
check_public() { # <url> <rota>
  local res status final fpath rpath
  case "$1" in file://*) return 0 ;; esac
  res=$(curl -sL --max-time 15 -o /dev/null -w '%{http_code} %{url_effective}' "$1" 2>/dev/null) || return 0
  status="${res%% *}"; final="${res#* }"
  case "$status" in 401|403) return 1 ;; 404|410) return 2 ;; 5??) return 3 ;; esac
  fpath="/${final#*://*/}"; fpath="${fpath%%\?*}"; fpath="${fpath%/}"
  rpath="${2%%\?*}"; rpath="${rpath%/}"
  if [ "$fpath" != "$rpath" ] && printf '%s' "$fpath" | grep -Eqi "$login_re"; then return 1; fi
  return 0
}

ok=0; fail=0; skipped=0
skipped_list=""
IFS=',' read -r -a route_list <<< "$routes"
IFS=',' read -r -a vp_list <<< "$viewports"

for route in "${route_list[@]}"; do
  route="${route// /}"
  [ -z "$route" ] && continue
  case "$route" in /*) ;; *) route="/$route" ;; esac
  url="${base_url%/}${route}"
  [ "$route" = "/" ] && url="${base_url%/}/"
  name=$(slug "$route")
  check_public "$url" "$route"
  case $? in
    1) echo "pulada  $route: exige login (só telas públicas). Peça ao usuário a imagem em .swarm/references/." >&2
       skipped=$((skipped + 1)); skipped_list="$skipped_list $route"; continue ;;
    2) echo "FALHA   $route: 404 (rota não existe)" >&2; fail=$((fail + 1)); continue ;;
    3) echo "FALHA   $route: erro de servidor" >&2; fail=$((fail + 1)); continue ;;
  esac
  for vp in "${vp_list[@]}"; do
    vp="${vp// /}"
    vname="${vp%%=*}"
    size="${vp#*=}"
    w="${size%x*}"; h="${size#*x}"
    case "$w$h" in *[!0-9]*|"") echo "capture: viewport inválido: $vp" >&2; fail=$((fail + 1)); continue ;; esac
    file="$out/${name}-${vname}.png"
    ua=""
    [ "$w" -le 600 ] && ua="$mobile_ua"
    rm -f "$file"
    timeout 90 "$chrome" --headless=new --disable-gpu --hide-scrollbars $sandbox \
      --window-size="${w},${h}" --force-device-scale-factor="$scale" \
      ${ua:+--user-agent="$ua"} --virtual-time-budget="$wait_ms" \
      --screenshot="$file" "$url" >/dev/null 2>&1
    if [ -s "$file" ]; then
      echo "ok   $file  ($url, ${w}x${h})"
      ok=$((ok + 1))
    else
      echo "FALHA $url ${w}x${h}" >&2
      fail=$((fail + 1))
    fi
  done
done

echo "capture: $ok capturas, $fail falhas, $skipped puladas${skipped_list:+ (login:$skipped_list)}. Confira dados sensíveis nas imagens antes de versionar."
[ "$fail" -gt 0 ] && exit 1
[ "$ok" -eq 0 ] && [ "$skipped" -gt 0 ] && exit 5
exit 0
