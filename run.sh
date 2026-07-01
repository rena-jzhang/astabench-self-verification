#!/usr/bin/env bash
# AstaBench cloud bootstrap — run on a fresh Ubuntu VM (>=16 vCPU / 32-64GB RAM / 60GB disk).
# Usage: OPENAI_API_KEY=sk-... HF_TOKEN=hf_... bash cloud_bootstrap.sh
set -euo pipefail

: "${OPENAI_API_KEY:?set OPENAI_API_KEY}"
: "${HF_TOKEN:?set HF_TOKEN}"
N="${N:-8}"                 # problems (parallelism)
MODEL="${MODEL:-openai/gpt-4.1-mini}"
WORK="${WORK:-$HOME/asta}"

echo "### 1. system deps (docker, git, curl, build) ###"
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
# disable containerd image store (README fix for sandbox unpack timeouts)
sudo mkdir -p /etc/docker
echo '{"features":{"containerd-snapshotter":false}}' | sudo tee /etc/docker/daemon.json >/dev/null
sudo systemctl restart docker || sudo service docker restart || true
sudo usermod -aG docker "$USER" || true

echo "### 2. uv ###"
command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

echo "### 3. clone repos ###"
mkdir -p "$WORK" && cd "$WORK"
[ -d asta-bench ]      || git clone --recursive --branch v0.3.1 https://github.com/allenai/asta-bench.git
[ -d agent-baselines ] || git clone https://github.com/allenai/agent-baselines.git
cd "$WORK/asta-bench" && uv sync

echo "### 4. drop in the verified_react solver ###"
mkdir -p "$WORK/agent-baselines/agent_baselines/solvers/verified_react"
# NOTE: scp verified_react.py to this path before running, OR it is embedded below.
VR="$WORK/agent-baselines/agent_baselines/solvers/verified_react/verified_react.py"
if [ ! -f "$VR" ]; then echo "!! verified_react.py missing at $VR — scp it first"; fi

echo "### 5. env ###"
export OPENAI_API_KEY HF_TOKEN
huggingface_ok=$(python3 - <<PY 2>/dev/null || true
print("ok")
PY
)

echo "### 6. run baseline + verified (throttle sandboxes to N, containerd fix applied) ###"
cd "$WORK/asta-bench"
run () { # $1=solver-arg $2=logdir
  uv run inspect eval astabench/discoverybench_validation \
    --solver "$1" --model "$MODEL" --limit "$N" \
    --max-samples "$N" --max-sandboxes "$N" \
    --log-dir "$2"
}
echo "== BASELINE =="
run "../agent-baselines/agent_baselines/solvers/react/basic_agent.py@instantiated_basic_agent" logs/baseline
echo "== VERIFIED =="
run "$VR@verified_react" logs/verified

echo "### 7. scores ###"
for d in logs/baseline logs/verified; do
  f=$(ls -t "$d"/*.eval | head -1)
  echo "### $d ###"
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
echo "### DONE ###"
