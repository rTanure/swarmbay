#!/usr/bin/env python3
"""Relatório de observabilidade do swarmbay: quem foi chamado, para quê, quanto durou,
quantos tokens gastou e em qual modelo, incluindo o orquestrador.

Fonte: os transcritos que o Claude Code já grava em disco
  <config>/projects/<projeto>/<sessão>.jsonl                      (orquestrador)
  <config>/projects/<projeto>/<sessão>/subagents/agent-*.jsonl    (um por subagente)
  <config>/projects/<projeto>/<sessão>/subagents/agent-*.meta.json (tipo e description)

Só lê números e rótulos; nunca imprime prompts nem respostas.

Convenção de rótulo (o orquestrador a usa na description do Agent e no início de cada SendMessage):
  T-NNN <etapa> r<rodada> <lente>        ex.: "T-002 revisoes r2 security"
  etapas: spec design testes auditoria dev revisoes mapa

Uso:
  swarm-report.py [--session latest|ID|all] [--task T-NNN] [--cwd DIR]
                  [--prices ARQUIVO] [--json] [--md] [--save]
"""
import argparse
import glob
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime

CEILINGS = {"revisoes": 2, "auditoria": 2}  # rodadas de correção (r1 é a revisão inicial)
STATEFUL = {"tester", "developer", "designer", "spec-writer", "test-auditor"}  # devem ser retomados
STAGES = "spec|design|testes|auditoria|dev|revisoes|mapa"
LABEL_RE = re.compile(rf"(T-\d+)\s+({STAGES})\b(?:\s+r(\d+))?\s*(.*)", re.I)
BRACKET_RE = re.compile(r"^\s*\[([^\]]+)\]")


def config_dir():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")


def project_dir(cwd):
    return os.path.join(config_dir(), "projects", re.sub(r"[^A-Za-z0-9]", "-", os.path.abspath(cwd)))


def read_jsonl(path):
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                try:
                    yield json.loads(line)
                except ValueError:
                    continue
    except OSError:
        return


def ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        return None


def zero():
    return {"in": 0, "out": 0, "cache_read": 0, "cache_write": 0}


def add(a, b):
    for k in a:
        a[k] += b[k]


def total(t):
    return t["in"] + t["out"] + t["cache_read"] + t["cache_write"]


def from_usage(u):
    return {
        "in": u.get("input_tokens", 0) or 0,
        "out": u.get("output_tokens", 0) or 0,
        "cache_read": u.get("cache_read_input_tokens", 0) or 0,
        "cache_write": u.get("cache_creation_input_tokens", 0) or 0,
    }


def is_prompt(o):
    """Entrada de usuário que inicia um turno (prompt inicial ou mensagem de continuação)."""
    m = o.get("message")
    if o.get("type") != "user" or not isinstance(m, dict) or o.get("isMeta"):
        return None
    c = m.get("content")
    if isinstance(c, str):
        return c if c.strip() else None
    if isinstance(c, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
            return None
        texts = [b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text"]
        return "\n".join(texts) if any(t.strip() for t in texts) else None
    return None


def assistant_messages(entries, sidechain=None):
    """Mensagens do assistente sem dupla contagem (o mesmo message.id aparece em várias linhas)."""
    best = {}
    tools = defaultdict(set)
    for i, o in enumerate(entries):
        m = o.get("message")
        if not isinstance(m, dict) or m.get("role") != "assistant":
            continue
        if sidechain is not None and bool(o.get("isSidechain")) != sidechain:
            continue
        u = m.get("usage")
        if not isinstance(u, dict):
            continue
        mid = m.get("id") or o.get("uuid") or str(i)
        cur = best.get(mid)
        if cur is None:
            best[mid] = {"i": i, "usage": u, "model": m.get("model"), "ts": o.get("timestamp")}
        elif (u.get("output_tokens") or 0) >= (cur["usage"].get("output_tokens") or 0):
            cur.update(usage=u, ts=o.get("timestamp") or cur["ts"], model=m.get("model") or cur["model"])
        c = m.get("content")
        if isinstance(c, list):
            for b in c:
                if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("id"):
                    tools[mid].add(b["id"])
    return best, tools


def parse_label(text):
    """Extrai (tarefa, etapa, rodada, lente) de um rótulo; None se não seguir a convenção."""
    if not text:
        return None
    mt = LABEL_RE.search(text)
    if not mt:
        return None
    return {"task": mt.group(1).upper(), "stage": mt.group(2).lower(),
            "round": int(mt.group(3)) if mt.group(3) else None, "lens": mt.group(4).strip()}


def analyze_subagent(path):
    entries = list(read_jsonl(path))
    meta = {}
    try:
        with open(path[:-len(".jsonl")] + ".meta.json", encoding="utf-8") as fh:
            meta = json.load(fh)
    except (OSError, ValueError):
        pass
    agent_id = next((o["agentId"] for o in entries if o.get("agentId")), os.path.basename(path))
    starts = [(i, is_prompt(o), o.get("timestamp")) for i, o in enumerate(entries) if is_prompt(o)]
    best, tools = assistant_messages(entries)
    turns = []
    for n, (i, text, t0) in enumerate(starts):
        label = None
        if n == 0:
            label = meta.get("description")
        else:
            br = BRACKET_RE.match(text or "")
            label = br.group(1) if br else None
        turns.append({"label": label, "start": ts(t0), "end": ts(t0), "tokens": zero(), "tools": 0, "models": set()})
    if not turns:
        turns.append({"label": meta.get("description"), "start": None, "end": None, "tokens": zero(), "tools": 0, "models": set()})
        starts = [(0, "", None)]
    for mid, b in best.items():
        idx = max((k for k, s in enumerate(starts) if s[0] <= b["i"]), default=0)
        t = turns[idx]
        add(t["tokens"], from_usage(b["usage"]))
        t["tools"] += len(tools.get(mid, ()))
        if b["model"]:
            t["models"].add(b["model"])
        e = ts(b["ts"])
        if e and (t["end"] is None or e > t["end"]):
            t["end"] = e
        if e and t["start"] is None:
            t["start"] = e
    prev = None
    for t in turns:
        lab = parse_label(t["label"])
        if lab is None and prev is not None and t is not turns[0]:
            lab = dict(prev, round=None)  # continuação sem rótulo herda a tarefa/etapa
        t["parsed"] = lab
        prev = lab or prev
        t["wall"] = (t["end"] - t["start"]).total_seconds() if t["start"] and t["end"] else 0.0
    return {
        "agent_id": agent_id,
        "type": (meta.get("agentType") or "?").split(":")[-1],
        "plugin": (meta.get("agentType") or "").split(":")[0] if ":" in (meta.get("agentType") or "") else "",
        "description": meta.get("description") or "",
        "turns": turns,
    }


def analyze_session(proj, sid):
    main = list(read_jsonl(os.path.join(proj, sid + ".jsonl")))
    best, _ = assistant_messages(main, sidechain=False)
    orch = {"tokens": zero(), "models": defaultdict(zero), "messages": len(best)}
    for b in best.values():
        t = from_usage(b["usage"])
        add(orch["tokens"], t)
        add(orch["models"][b["model"] or "?"], t)
    stamps = [ts(o.get("timestamp")) for o in main if o.get("timestamp")]
    stamps = [s for s in stamps if s]
    agents = [analyze_subagent(p) for p in sorted(glob.glob(os.path.join(proj, sid, "subagents", "agent-*.jsonl")))]
    return {"session": sid, "orchestrator": orch, "agents": agents,
            "span": (max(stamps) - min(stamps)).total_seconds() if stamps else 0.0}


def load_prices(path):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        return {k: v for k, v in data.items() if isinstance(v, dict) and not k.startswith("_")}
    except (OSError, ValueError):
        return {}


def cost_of(tokens, price):
    if not price or any(price.get(k) is None for k in ("input", "output")):
        return None
    return (tokens["in"] * price["input"] + tokens["out"] * price["output"]
            + tokens["cache_read"] * (price.get("cache_read") or 0)
            + tokens["cache_write"] * (price.get("cache_write") or 0)) / 1e6


def fk(n):
    return f"{n / 1000:.1f}k" if n >= 1000 else str(n)


def fd(s):
    s = int(round(s))
    return f"{s // 3600}h{(s % 3600) // 60:02d}m" if s >= 3600 else (f"{s // 60}m{s % 60:02d}s" if s >= 60 else f"{s}s")


def table(rows, header):
    rows = [header] + rows
    w = [max(len(str(r[i])) for r in rows) for i in range(len(header))]
    out = []
    for n, r in enumerate(rows):
        out.append("  ".join(str(c).ljust(w[i]) if i == 0 else str(c).rjust(w[i]) for i, c in enumerate(r)))
        if n == 0:
            out.append("  ".join("-" * x for x in w))
    return "\n".join(out)


def build(sessions, task_filter, prices):
    calls = []
    for s in sessions:
        for a in s["agents"]:
            for n, t in enumerate(a["turns"]):
                lab = t["parsed"]
                if task_filter and (not lab or lab["task"] != task_filter):
                    continue
                price = prices.get(next(iter(t["models"]), ""))
                calls.append({
                    "session": s["session"], "agent_id": a["agent_id"], "type": a["type"], "turn": n,
                    "kind": "lançamento" if n == 0 else "retomada",
                    "task": lab["task"] if lab else None, "stage": lab["stage"] if lab else None,
                    "round": lab["round"] if lab else None, "lens": lab["lens"] if lab else "",
                    "model": ",".join(sorted(t["models"])) or "?", "tokens": t["tokens"], "tools": t["tools"],
                    "wall": t["wall"], "cost": cost_of(t["tokens"], price),
                })
    return calls


def alerts(sessions, calls):
    out = []
    unl = sum(1 for c in calls if not c["task"])
    if unl:
        out.append(f"{unl} chamada(s) sem rótulo 'T-NNN etapa rN lente': não entram nos totais por tarefa/etapa.")
    launches = defaultdict(set)
    for c in calls:
        if c["task"] and c["type"] in STATEFUL:
            launches[(c["task"], c["type"])].add(c["agent_id"])
    for (task, typ), ids in sorted(launches.items()):
        if len(ids) > 1:
            out.append(f"{task}: '{typ}' foi lançado {len(ids)} vezes (cold start); deveria ser retomado com SendMessage.")
    rounds = defaultdict(int)
    for c in calls:
        if c["task"] and c["stage"] in CEILINGS and c["round"]:
            rounds[(c["task"], c["stage"])] = max(rounds[(c["task"], c["stage"])], c["round"])
    for (task, stage), r in sorted(rounds.items()):
        corr = r - 1
        if corr > CEILINGS[stage]:
            out.append(f"{task}: {stage} teve {corr} rodadas de correção (teto {CEILINGS[stage]}).")
    return out, rounds


def render_text(sessions, calls, prices):
    lines = []
    orch = defaultdict(zero)
    span = 0.0
    for s in sessions:
        add(orch["_"], s["orchestrator"]["tokens"])
        span += s["span"]
    sub = zero()
    for c in calls:
        add(sub, c["tokens"])
    o_t, s_t = total(orch["_"]), total(sub)
    lines.append(f"Sessões: {len(sessions)} | período total: {fd(span)}")
    lines.append(f"Tokens: orquestrador {fk(o_t)} | subagentes {fk(s_t)} | total {fk(o_t + s_t)}"
                 f"  (orquestrador = {100 * o_t / max(o_t + s_t, 1):.0f}%)")
    for s in sessions:
        for m, t in s["orchestrator"]["models"].items():
            lines.append(f"  orquestrador em {m}: in {fk(t['in'])}, out {fk(t['out'])}, "
                         f"cache lido {fk(t['cache_read'])}, cache criado {fk(t['cache_write'])}")
    denom = orch["_"]["in"] + orch["_"]["cache_read"] + orch["_"]["cache_write"] + sub["in"] + sub["cache_read"] + sub["cache_write"]
    if denom:
        lines.append(f"Cache: {100 * (orch['_']['cache_read'] + sub['cache_read']) / denom:.0f}% da entrada veio de cache")
    costs = [c["cost"] for c in calls if c["cost"] is not None]
    if prices and costs:
        lines.append(f"Custo estimado dos subagentes: US$ {sum(costs):.2f}"
                     f"{'' if len(costs) == len(calls) else ' (parcial: há modelos sem preço)'}")

    by_stage = defaultdict(lambda: {"t": zero(), "wall": 0.0, "n": 0, "tools": 0})
    for c in calls:
        k = (c["task"] or "(sem rótulo)", c["stage"] or "-")
        add(by_stage[k]["t"], c["tokens"])
        by_stage[k]["wall"] += c["wall"]
        by_stage[k]["n"] += 1
        by_stage[k]["tools"] += c["tools"]
    rows = [[k[0], k[1], v["n"], fk(total(v["t"])), fk(v["t"]["out"]), fd(v["wall"]), v["tools"]]
            for k, v in sorted(by_stage.items())]
    lines += ["", "Por tarefa e etapa (subagentes)", table(rows, ["tarefa", "etapa", "chamadas", "tokens", "saída", "tempo", "tools"])]

    by_agent = defaultdict(lambda: {"t": zero(), "wall": 0.0, "launch": 0, "resume": 0, "models": set()})
    for c in calls:
        v = by_agent[c["type"]]
        add(v["t"], c["tokens"])
        v["wall"] += c["wall"]
        v["launch" if c["turn"] == 0 else "resume"] += 1
        v["models"].add(c["model"])
    rows = [[k, ",".join(sorted(v["models"])), v["launch"], v["resume"], fk(total(v["t"])), fd(v["wall"])]
            for k, v in sorted(by_agent.items(), key=lambda kv: -total(kv[1]["t"]))]
    lines += ["", "Por agente", table(rows, ["agente", "modelo", "lançamentos", "retomadas", "tokens", "tempo"])]

    top = sorted(calls, key=lambda c: -total(c["tokens"]))[:12]
    rows = [[c["task"] or "-", c["stage"] or "-", f"r{c['round']}" if c["round"] else "-", c["type"], c["lens"][:14],
             c["kind"], c["model"].replace("claude-", ""), fk(total(c["tokens"])), fd(c["wall"])] for c in top]
    lines += ["", "Chamadas mais caras", table(rows, ["tarefa", "etapa", "rod", "agente", "lente", "tipo", "modelo", "tokens", "tempo"])]

    al, _ = alerts(sessions, calls)
    if al:
        lines += ["", "Alertas"] + [f"  - {a}" for a in al]
    lines += ["", "Obs.: 'tempo' é o tempo de relógio de cada chamada (inclui espera por comandos), não tempo de modelo."]
    return "\n".join(lines)


def render_md(calls, task):
    by = defaultdict(lambda: {"t": zero(), "wall": 0.0, "n": 0, "agents": set()})
    for c in calls:
        v = by[c["stage"] or "-"]
        add(v["t"], c["tokens"])
        v["wall"] += c["wall"]
        v["n"] += 1
        v["agents"].add(c["type"])
    rows = ["| etapa | chamadas | agentes | tokens | tempo |", "|---|---|---|---|---|"]
    allt = zero()
    wall = 0.0
    for k, v in sorted(by.items()):
        rows.append(f"| {k} | {v['n']} | {', '.join(sorted(v['agents']))} | {fk(total(v['t']))} | {fd(v['wall'])} |")
        add(allt, v["t"])
        wall += v["wall"]
    rows.append(f"| **total** | {sum(v['n'] for v in by.values())} | | **{fk(total(allt))}** | {fd(wall)} |")
    _, rounds = alerts([], calls)
    extra = ", ".join(f"{s}: {r - 1} rodada(s) de correção" for (t, s), r in sorted(rounds.items()) if r)
    return f"## Custo ({task})\n\n" + "\n".join(rows) + (f"\n\nRodadas: {extra}\n" if extra else "\n") + \
        "\n(gerado por scripts/swarm-report.py; só subagentes, o orquestrador não está incluído)\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--session", default="latest", help="latest (padrão), um id, ou all")
    ap.add_argument("--task", help="filtra por tarefa, ex.: T-002")
    ap.add_argument("--cwd", default=os.getcwd(), help="diretório do projeto (padrão: atual)")
    ap.add_argument("--prices", help="JSON de preços por modelo (padrão: .swarm/prices.json se existir)")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--md", action="store_true", help="bloco Markdown 'Custo' para o arquivo da tarefa (use com --task)")
    ap.add_argument("--save", action="store_true", help="grava o JSON em .swarm/telemetry/")
    a = ap.parse_args()

    proj = project_dir(a.cwd)
    mains = sorted(glob.glob(os.path.join(proj, "*.jsonl")), key=os.path.getmtime)
    if not mains:
        print(f"report: nenhum transcrito em {proj}", file=sys.stderr)
        return 2
    ids = [os.path.basename(p)[:-6] for p in mains]
    chosen = ids if a.session == "all" else [a.session if a.session != "latest" else ids[-1]]
    if a.session not in ("latest", "all") and a.session not in ids:
        print(f"report: sessão {a.session} não encontrada em {proj}", file=sys.stderr)
        return 2
    prices_path = a.prices or os.path.join(a.cwd, ".swarm", "prices.json")
    prices = load_prices(prices_path)
    sessions = [analyze_session(proj, sid) for sid in chosen]
    task = a.task.upper() if a.task else None
    calls = build(sessions, task, prices)

    if a.md:
        if not task:
            print("report: --md exige --task T-NNN", file=sys.stderr)
            return 4
        print(render_md(calls, task))
        return 0
    payload = {"sessions": [{"session": s["session"], "span_s": s["span"],
                             "orchestrator": {"tokens": s["orchestrator"]["tokens"],
                                              "models": dict(s["orchestrator"]["models"])}} for s in sessions],
               "calls": calls, "alerts": alerts(sessions, calls)[0]}
    if a.save:
        out = os.path.join(a.cwd, ".swarm", "telemetry")
        os.makedirs(out, exist_ok=True)
        dest = os.path.join(out, f"{chosen[-1] if len(chosen) == 1 else 'all'}.json")
        with open(dest, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=1, default=str)
        print(f"report: salvo em {dest}", file=sys.stderr)
    print(json.dumps(payload, ensure_ascii=False, indent=1, default=str) if a.json else render_text(sessions, calls, prices))
    return 0


if __name__ == "__main__":
    sys.exit(main())
