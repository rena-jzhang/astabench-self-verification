#!/usr/bin/env bash
# Best-practice AstaBench run: astabench eval (reproducible, submittable) on Docker sandbox,
# ReAct baseline vs verified_react on DiscoveryBench. Resumable: re-run to pick up after a crash.
# Usage: OPENAI_API_KEY=sk-... HF_TOKEN=hf_... [MODEL=openai/gpt-5.5] [N=8] bash run.sh
set -uo pipefail
: "${OPENAI_API_KEY:?set OPENAI_API_KEY}"; : "${HF_TOKEN:?set HF_TOKEN}"; export OPENAI_API_KEY HF_TOKEN
MODEL="${MODEL:-openai/gpt-4.1-mini}"; N="${N:-8}"
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HOME/.local/bin:$PATH"
command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh

cd ~
[ -d asta-bench ]      || git clone --recursive --branch v0.3.1 https://github.com/allenai/asta-bench.git
[ -d agent-baselines ] || git clone https://github.com/allenai/agent-baselines.git
cd ~/asta-bench && uv sync
mkdir -p ~/agent-baselines/agent_baselines/solvers/verified_react
cp "$HERE/verified_react.py" ~/agent-baselines/agent_baselines/solvers/verified_react/verified_react.py

# --- Docker is REQUIRED (the intended sandbox). Start dockerd if not running. ---
if ! docker info >/dev/null 2>&1; then
  command -v dockerd >/dev/null || curl -fsSL https://get.docker.com | sh
  mkdir -p /etc/docker; printf '%s' '{"features":{"containerd-snapshotter":false}}' > /etc/docker/daemon.json
  pkill dockerd 2>/dev/null || true; sleep 2
  nohup dockerd --storage-driver=vfs --iptables=false >/tmp/dockerd.log 2>&1 & sleep 12
fi
if ! docker info >/dev/null 2>&1; then
  echo "!! Docker could not start on this box. AstaBench needs Docker; use a Docker-capable VM."
  echo "--- dockerd log ---"; tail -20 /tmp/dockerd.log; exit 1
fi
echo "docker OK: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"

# --- astabench eval (wrapper over inspect eval-set; reproducible metadata). Resumable. ---
run () { # $1 solver-arg  $2 log-dir
  uv run astabench eval --task DiscoveryBench --split validation --limit "$N" \
    --solver "$1" --model "$MODEL" --max-samples 2 --max-sandboxes 2 --log-dir "$2"
}
cd ~/asta-bench
echo "### BASELINE (model=$MODEL n=$N) ###"
run "../agent-baselines/agent_baselines/solvers/react/basic_agent.py@instantiated_basic_agent" logs/baseline
echo "### VERIFIED ###"
run "../agent-baselines/agent_baselines/solvers/verified_react/verified_react.py@verified_react" logs/verified

echo "### SCORES ###"
uv run astabench score logs/baseline 2>/dev/null || true
uv run astabench score logs/verified 2>/dev/null || true
for d in logs/baseline logs/verified; do
  f=$(ls -t "$d"/*.eval 2>/dev/null | head -1); [ -z "$f" ] && continue
  echo "## $d ##"; uv run python - "$f" <<'PY'
import sys; from inspect_ai.log import read_eval_log
lg=read_eval_log(sys.argv[1]); r=lg.results
print("status:", lg.status)
if r:
  print("samples:", r.completed_samples,"/",r.total_samples)
  for s in r.scores:
    for m,v in s.metrics.items(): print("  ",s.name,m,"=",round(v.value,4))
print("  tokens:", sum(u.total_tokens for u in (lg.stats.model_usage or {}).values()))
PY
done
echo "### DONE (re-run this script to resume any interrupted samples) ###"
