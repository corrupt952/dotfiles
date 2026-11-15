import { test, expect } from 'claude-code/testing'

const DENIAL =
  'Permission for this action was denied by the Claude Code auto mode classifier. Reason: Pushing to the default branch. If you have other tasks that don\'t depend on this action, continue working on those.'

function engineBelow(on, answer) {
  on('tool.call', async () => answer)
}

const call = ($, agentId) => $.tool.call({ tool: 'Bash', command: 'git push origin main', ...(agentId ? { agentId } : {}) })

test('a classifier block in the main loop gets the AskUserQuestion hint', async ($, on) => {
  engineBelow(on, { isError: true, result: DENIAL, text: DENIAL })
  const r = await call($)
  expect(r.isError).toBe(true)
  expect(r.text).toBe(DENIAL)
  expect(r.context.length).toBe(1)
  expect(r.context[0]).toContain('AskUserQuestion')
})

test('a classifier block in a subagent tells it to report to its parent', async ($, on) => {
  engineBelow(on, { isError: true, result: DENIAL, text: DENIAL })
  const r = await call($, 'a1')
  expect(r.context[0]).toContain('agent that launched you')
  expect(r.context[0].includes('AskUserQuestion')).toBe(false)
})

test('a refusal from the person gets nothing', async ($, on) => {
  const text = "The user doesn't want to proceed with this tool use. The tool use was rejected."
  engineBelow(on, { isError: true, result: text, text })
  const r = await call($)
  expect(r.context ?? []).toEqual([])
})

test('a hook block gets nothing', async ($, on) => {
  const text = 'PreToolUse:Bash hook error: Force-pushing is blocked by a static rule in settings.json.'
  engineBelow(on, { isError: true, result: text, text })
  const r = await call($)
  expect(r.context ?? []).toEqual([])
})

test('a successful call gets nothing', async ($, on) => {
  engineBelow(on, { result: { stdout: 'ok' }, text: 'ok' })
  const r = await call($)
  expect(r.context ?? []).toEqual([])
})
