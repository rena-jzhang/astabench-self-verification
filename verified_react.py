"""Self-verification ReAct solver for AstaBench.

This wraps the AstaBench ReAct baseline (`instantiated_basic_agent`) and adds
ONE improvement: after the agent produces its draft answer, a second LLM call
critiques that answer against the task and revises it if needed.

The falsifiable claim being tested:
    "A lightweight self-verification step added to a ReAct agent improves
    DiscoveryBench accuracy enough to move the accuracy-vs-cost Pareto frontier."

Design notes:
- This is the SIMPLEST first cut: a post-hoc wrapper. The base ReAct loop runs
  to completion (it calls submit() and writes a submission), then we run one
  extra verification turn and overwrite the final answer if the check changes it.
- A more faithful version would fold the check INSIDE the loop (before submit()
  fires) so a failed check lets the agent keep working with its tools. That is a
  later iteration; this wrapper is enough to measure whether verification helps.
"""

from logging import getLogger

from agent_baselines.solvers.react.basic_agent import instantiated_basic_agent
from astabench.tools.submission import get_submission_manager
from inspect_ai.model import ChatMessageUser, get_model
from inspect_ai.solver import Generate, Solver, TaskState, solver

logger = getLogger(__name__)

# Conservative verification turn. Default to KEEPING the draft; only replace it
# when the checker finds a concrete, demonstrable error. This avoids the failure
# mode where an over-eager verifier overturns a correct answer or breaks the
# required output format (which dropped accuracy in the first n=8 run).
VERIFY_PROMPT = """You proposed the following answer to the task above:

--- PROPOSED ANSWER ---
{draft}
--- END PROPOSED ANSWER ---

Act as a careful checker. Look ONLY for a concrete, demonstrable error in the
proposed answer, using the task description and the data/tool results above:
- a clear logical or arithmetic mistake,
- a claim that directly contradicts the data,
- a definite violation of the required output format.

Be conservative. If you are not highly confident there is a real error, KEEP the
answer. Do NOT rewrite for style, do NOT second-guess a defensible answer, and
do NOT change the output format.

Respond with a JSON object ONLY, no preamble:
{{"verdict": "keep" | "revise",
  "revised_answer": "<if revise: the corrected answer in EXACTLY the same format as the proposed answer; if keep: empty string>"}}"""


@solver
def verified_react(max_steps: int = 100, **tool_options) -> Solver:
    """ReAct baseline + one self-verification turn before the answer is final.

    Args:
        max_steps: Max reasoning steps for the underlying ReAct loop.
        **tool_options: Passed straight through to the ReAct baseline
            (ToolsetConfig options, e.g. with_stateful_python).
    """
    # The unmodified AstaBench ReAct baseline.
    base = instantiated_basic_agent(max_steps=max_steps, **tool_options)

    async def solve(state: TaskState, generate: Generate) -> TaskState:
        # 1. Run the normal ReAct loop -> produces a draft answer + submission.
        state = await base(state, generate)

        # 2. Grab whatever the agent submitted as its draft answer.
        draft = state.output.completion if state.output else ""
        if not draft or not draft.strip():
            # Nothing to verify (agent never produced an answer); leave as-is.
            logger.info("verified_react: empty draft, skipping verification.")
            return state

        # 3. One conservative verification turn. The checker returns a JSON
        #    verdict; we only replace the answer when it confidently flags an
        #    error AND returns a non-empty revision. Otherwise we leave the draft
        #    (and its structured submission) completely untouched.
        import json as _json

        verify_msg = ChatMessageUser(content=VERIFY_PROMPT.format(draft=draft))
        check = await get_model().generate(input=state.messages + [verify_msg])
        raw = (check.message.text or "").strip()

        verdict, revised = "keep", ""
        try:
            # tolerate ```json fences / surrounding prose
            s = raw[raw.find("{"): raw.rfind("}") + 1]
            obj = _json.loads(s)
            verdict = str(obj.get("verdict", "keep")).lower()
            revised = (obj.get("revised_answer") or "").strip()
        except Exception as e:  # noqa: BLE001 - bad JSON => keep the draft
            logger.info("verified_react: unparseable verdict, keeping draft (%s).", e)

        # record the exchange for transparency
        state.messages.append(verify_msg)
        state.messages.append(check.message)

        # 4. Only overwrite on a confident, non-empty revision.
        if verdict == "revise" and revised and revised != draft.strip():
            logger.info("verified_react: verification REVISED the answer.")
            if state.output:
                state.output.completion = revised
            try:
                mgr = get_submission_manager()
                if mgr is not None:
                    mgr.write_submission(revised)
            except Exception as e:  # noqa: BLE001 - never let verification crash the run
                logger.info("verified_react: could not re-write submission (%s).", e)
        else:
            logger.info("verified_react: verification KEPT the answer (no change).")

        return state

    return solve
