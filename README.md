# Self-Verification for Scientific-Research Agents (AstaBench / DiscoveryBench)

A small, focused research artifact: take [AI2 AstaBench](https://allenai.org/asta/bench)'s
open **ReAct baseline agent** and add **one change** — a conservative **self-verification step** —
then measure whether it improves accuracy on the **DiscoveryBench** data-analysis task, on the
accuracy-vs-cost Pareto frontier the leaderboard reports.

## The question
> Does adding a lightweight self-verification step to a ReAct agent improve DiscoveryBench
> accuracy without a disproportionate increase in cost — and is this measured on AstaBench yet?

**Novelty:** as of this writing, no solver in AstaBench's public
[`agent-baselines`](https://github.com/allenai/agent-baselines) implements self-verification /
critique / reflexion (checked by reading + grepping every baseline). So this is an open angle.

## The method (`verified_react.py`)
Wrap the unmodified AstaBench ReAct baseline. After it produces a draft answer, run **one**
extra LLM turn that acts as a careful checker and returns a JSON verdict:
- `keep` → leave the draft (and its structured submission) untouched, or
- `revise` → replace only when it is **confident** there is a concrete error, preserving format.

It is deliberately **conservative** — an earlier aggressive version that always re-derived the
answer *hurt* accuracy by overturning correct answers, so the checker now defaults to keeping.

## How to run
Requires a Docker-capable Linux box (AstaBench uses a Docker sandbox for code execution),
an OpenAI key, and a HuggingFace token (the DiscoveryBench dataset is gated).

```bash
OPENAI_API_KEY=sk-...  HF_TOKEN=hf_...  MODEL=openai/gpt-5.5  N=8  bash run.sh
```
`run.sh` installs `uv`, clones `asta-bench` + `agent-baselines`, places the solver, starts Docker,
and runs the ReAct baseline vs `verified_react` with `astabench eval` (reproducible logs). It is
**resumable** — re-run to pick up interrupted samples.

## Results
See [`RESULTS.md`](RESULTS.md). (Preliminary n=8 numbers on a cheap model; a gpt-5.5 run is the
real test — a weak base model scores near the floor, leaving little for verification to fix.)

## Files
| file | what |
|---|---|
| `verified_react.py` | the solver (ReAct + conservative self-verification) |
| `run.sh` | one-shot best-practice setup + baseline-vs-verified run |
| `RESULTS.md` | measured numbers + honest read |

## Credits
Built on AI2's [AstaBench](https://github.com/allenai/asta-bench) and
[agent-baselines](https://github.com/allenai/agent-baselines), which run on UK AISI's
[Inspect](https://inspect.aisi.org.uk/). Solver + experiment by
[@rena-jzhang](https://github.com/rena-jzhang).
