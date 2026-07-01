# Results

Task: `DiscoveryBench` (validation split), objective scorer `score_discoverybench/mean`.
Sandbox: Docker (via Inspect). Solvers: AstaBench ReAct baseline vs `verified_react`.

## n=8, gpt-5.5 (the real test — base model is off the accuracy floor)
| Solver | Accuracy | ±stderr | Tokens |
|---|---|---|---|
| ReAct baseline | **0.171** | 0.114 | ~488k |
| verified_react (conservative) | **0.042** | 0.042 | ~454k |

**Finding: self-verification HURTS here, consistently.** Verified lost to the baseline in every
run (gpt-4.1-mini v1 & v2, and gpt-5.5). With gpt-5.5 the baseline reaches 17% (a fair comparison,
not the noise floor), and verification drops it to 4%.

### Why (diagnosis)
DiscoveryBench's answer is a **structured submission** (a hypothesis object with variables +
relationships), written via the submission manager. The v1/v2 verifier inspects
`state.output.completion` — free text — which is *not* the scored object. When it "revises," it
writes free text over the structured submission and corrupts it. So this is not evidence that
self-verification is a bad idea in general; it shows a **free-text post-hoc verifier is incompatible
with structured-submission tasks.**

## Preliminary — n=8, gpt-4.1-mini (near the floor, kept for the record)
| Solver | Accuracy | ±stderr |
|---|---|---|
| ReAct baseline | 0.083 | 0.083 |
| verified (aggressive v1) | 0.042 | 0.042 |
| verified (conservative v2) | 0.050 | 0.050 |

## Next
Fix the mismatch: verify the **structured submission** (not `output.completion`), or apply
verification only to free-text-answer tasks (e.g. literature QA). Retest to see whether the idea
has legs once it checks the right object. If it still loses, this stands as a true negative result.
