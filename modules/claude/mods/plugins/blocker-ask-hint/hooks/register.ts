// The auto mode classifier's block reaches the model as the tool's error
// result, and Claude Code (2.1.325) starts that text with this prefix. Its own
// guidance after the reason says to stop and explain, so the model tends to
// end the turn with prose or drop the step. The hint below rides beside the
// result as context and leaves the block text untouched: Claude Code parses
// that text back by its exact shape.
//
// classic.PermissionDenied is not used: it can only answer `retry`, and a
// managed sec-default tier can pass over classic.* for installed plugins.
const CLASSIFIER_DENIAL = 'Permission for this action was denied by the Claude Code auto mode classifier. Reason: '

const MAIN_HINT =
  'The auto mode classifier blocked this call, not the user. If the action is clearly dangerous or goes beyond what the user asked for, leave it. If the user asked for this action, or it is a necessary step of what they asked, do not drop it silently or end the turn with only an explanation: ask the user for approval with the AskUserQuestion tool, naming the exact action and the classifier\'s reason. If they approve, retry the same call once; auto mode judges the retry with their approval in view.'

const SUBAGENT_HINT =
  'The auto mode classifier blocked this call, not the user. If the action is clearly dangerous or goes beyond your brief, leave it. If your brief needs this action, you cannot ask the user yourself: do not work around the block; report to the agent that launched you the exact call, the classifier\'s reason, and that it needs the user\'s approval.'

export function register(on) {
  on('tool.call', async ($, e, next) => {
    const r = await next(e)
    if (!r.isError || typeof r.text !== 'string' || !r.text.startsWith(CLASSIFIER_DENIAL)) return r
    const hint = e.agentId ? SUBAGENT_HINT : MAIN_HINT
    return { ...r, context: [...(r.context ?? []), hint] }
  })
}
