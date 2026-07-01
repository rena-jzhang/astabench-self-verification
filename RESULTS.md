# Results

Task: `DiscoveryBench` (validation split), objective scorer `score_discoverybench/mean`.
Sandbox: Docker (via Inspect). Solvers: AstaBench ReAct baseline vs `verified_react`.

## Preliminary — n=8, gpt-4.1-mini (noisy; near the accuracy floor)
| Solver | Accuracy | ±stderr | Tokens |
|---|---|---|---|
| ReAct baseline | 0.083 | 0.083 | ~359k |
| verified_react (aggressive v1) | 0.042 | 0.042 | ~346k |
| verified_react (conservative v2) | 0.050 | 0.050 | ~340k |

**Read:** all three are statistically indistinguishable (stderr > gaps) and near the floor — with a
cheap model the agent rarely gets close, so there is little for a verifier to rescue. This is *not*
a fair test of the idea; it mainly validates the pipeline.

## Next — gpt-5.5, n=8 (the real test)
A capable base model should push the agent into the "close-but-wrong" regime where verification can
actually help. *Pending.*
