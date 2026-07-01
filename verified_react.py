"""Self-verification ReAct solver for AstaBench.

Wraps the AstaBench ReAct baseline (`instantiated_basic_agent`) and adds ONE
improvement: after the agent submits its answer, a conservative verification turn
re-checks the ANSWER THE SCORER WILL SEE and only replaces it when it confidently
finds a concrete error.

Key correctness point: AstaBench tasks (incl. DiscoveryBench) are scored from the
*submission* written via the submission manager (`get_submission()`), NOT from
`state.output.completion`. So we verify and (if needed) rewrite the submission,
preserving its exact format. Verifying free text instead corrupts structured tasks.
"""

from logging import getLogger

from agent_baselines.solvers.react.basic_agent import instantiated_basic_agent
from astabench.tools.submission import get_submission_manager
from inspect_ai.model import ChatMessageUser, get_model
from inspect_ai.solver import Generate, Solver, TaskState, solver

logger = getLogger(__name__)

VERIFY_PROMPT = """The task above was answered with this submission:

--- SUBMISSION ---
{draft}
--- END SUBMISSION ---

Act as a careful checker. Look ONLY for a concrete, demonstrable error, using the
task description and the data/tool results in the conversation above:
- a clear logical or arithmetic mistake,
- a claim that directly contradicts the data,
- a definite violation of the required output/format.

Be conservative. If you are not highly confident there is a real error, KEEP the
submission. Do NOT rewrite for style, do NOT second-guess a defensible answer, and
do NOT change the format or structure.

Respond with a JSON object ONLY, no preamble:
{{"verdict": "keep" | "revise",
  "revised_submission": "<if revise: the corrected submission in EXACTLY the same format/structure as above; if keep: empty string>"}}"""


@solver
def verified_react(max_steps: int = 100, **tool_options) -> Solver:
    """ReAct baseline + one conservative self-verification turn on the submission."""
    base = instantiated_basic_agent(max_steps=max_steps, **tool_options)

    async def solve(state: TaskState, generate: Generate) -> TaskState:
        import json as _json

        state = await base(state, generate)

        # The scored answer is the submission, not output.completion.
        mgr = get_submission_manager()
        try:
            draft = mgr.get_submission() if mgr and mgr.has_submission() else ""
        except Exception:  # noqa: BLE001
            draft = ""
        if not draft or not draft.strip():
            draft = state.output.completion if state.output else ""
        if not draft or not draft.strip():
            logger.info("verified_react: no submission to verify; skipping.")
            return state

        verify_msg = ChatMessageUser(content=VERIFY_PROMPT.format(draft=draft))
        check = await get_model().generate(input=state.messages + [verify_msg])
        raw = (check.message.text or "").strip()

        verdict, revised = "keep", ""
        try:
            s = raw[raw.find("{"): raw.rfind("}") + 1]
            obj = _json.loads(s)
            verdict = str(obj.get("verdict", "keep")).lower()
            revised = (obj.get("revised_submission") or "").strip()
        except Exception as e:  # noqa: BLE001
            logger.info("verified_react: unparseable verdict, keeping (%s).", e)

        state.messages.append(verify_msg)
        state.messages.append(check.message)

        if verdict == "revise" and revised and revised != draft.strip():
            logger.info("verified_react: REVISED the submission.")
            try:
                if mgr is not None:
                    mgr.write_submission(revised)
            except Exception as e:  # noqa: BLE001
                logger.info("verified_react: could not rewrite submission (%s).", e)
            if state.output:
                state.output.completion = revised
        else:
            logger.info("verified_react: KEPT the submission (no change).")

        return state

    return solve
