# Self-verification agent for AstaBench (DiscoveryBench)

A minimal research artifact: take AI2 AstaBench's ReAct baseline agent and add **one change** —
a conservative **self-verification step** (after the agent answers, a second LLM pass checks the
answer and only overwrites it when it confidently finds a real error).

**Claim tested:** does self-verification improve accuracy on DiscoveryBench (data-analysis) on the
accuracy-vs-cost Pareto frontier? (No AstaBench baseline currently does self-verification.)

## Files
- `verified_react.py` — the solver (wraps `agent_baselines` ReAct + verification turn).
- `run.sh` — bootstrap: installs uv + Docker, clones asta-bench + agent-baselines, runs baseline vs verified.

## Run
```bash
OPENAI_API_KEY=sk-... HF_TOKEN=hf_... bash run.sh
```
Drop `verified_react.py` into `agent-baselines/agent_baselines/solvers/verified_react/`.

## Status
Pipeline verified; results in progress (comparing ReAct baseline vs verified on n=8, gpt-5.5).
