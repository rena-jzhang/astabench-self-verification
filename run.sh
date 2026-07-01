#!/usr/bin/env bash
# One-shot: set up AstaBench on a fresh Ubuntu box + run ReAct baseline vs verified_react
# on DiscoveryBench, then print both scores.
# Usage: OPENAI_API_KEY=sk-... HF_TOKEN=hf_... [MODEL=openai/gpt-5.5] [N=8] bash run.sh
set -uo pipefail
: "${OPENAI_API_KEY:?set OPENAI_API_KEY}"
: "${HF_TOKEN:?set HF_TOKEN}"
export OPENAI_API_KEY HF_TOKEN
MODEL="${MODEL:-openai/gpt-4.1-mini}"     # override to openai/gpt-5.5 for the real run
N="${N:-8}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "### deps: uv ###"
command -v uv >/dev/null || { curl -LsSf https://astral.sh/uv/install.sh | sh; }
export PATH="$HOME/.local/bin:$PATH"

echo "### clone asta-bench + agent-baselines ###"
cd ~
[ -d asta-bench ]      || git clone --recursive --branch v0.3.1 https://github.com/allenai/asta-bench.git
[ -d agent-baselines ] || git clone https://github.com/allenai/agent-baselines.git
cd ~/asta-bench && uv sync

echo "### place verified_react solver (from this repo) ###"
mkdir -p ~/agent-baselines/agent_baselines/solvers/verified_react
cp "$HERE/verified_react.py" ~/agent-baselines/agent_baselines/solvers/verified_react/verified_react.py

echo "### try to start docker (vfs, no iptables) — falls back to --sandbox local ###"
SANDBOX_FLAG=""
if ! docker info >/dev/null 2>&1; then
  if command -v dockerd >/dev/null || curl -fsSL https://get.docker.com | sh; then
    mkdir -p /etc/docker; printf '%s' '{"features":{"containerd-snapshotter":false}}' > /etc/docker/daemon.json
    pkill dockerd 2>/dev/null || true; sleep 2
    nohup dockerd --storage-driver=vfs --iptables=false >/tmp/dockerd.log 2>&1 &
    sleep 12
  fi
fi
if docker info >/dev/null 2>&1; then
  echo "docker OK -> native sandbox"
else
  echo "no docker -> --sandbox local (installing inspect-tool-support)"
  uv pip install inspect-tool-support >/dev/null 2>&1 || true
  uv run inspect-tool-support post-install >/dev/null 2>&1 || true
  ln -sf ~/asta-bench/.venv/bin/inspect-tool-support /usr/local/bin/ 2>/dev/null || true
  SANDBOX_FLAG="--sandbox local"
fi

run () { # $1 solver-arg  $2 logdir
  uv run inspect eval astabench/discoverybench_validation \
    --solver "$1" --model "$MODEL" --limit "$N" \
    --max-samples 2 --max-sandboxes 2 $SANDBOX_FLAG --log-dir "$2"
}
cd ~/asta-bench
echo "### RUN baseline (model=$MODEL n=$N) ###"
run "../agent-baselines/agent_baselines/solvers/react/basic_agent.py@instantiated_basic_agent" logs/baseline
echo "### RUN verified ###"
run "../agent-baselines/agent_baselines/solvers/verified_react/verified_react.py@verified_react" logs/verified

echo "### SCORES ###"
for d in logs/baseline logs/verified; do
  f=$(ls -t "$d"/*.eval | head -1)
  echo "## $d ##"
  uv run python - "$f" <<'PY'
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
echo "### DONE — compare baseline vs verified above ###"
