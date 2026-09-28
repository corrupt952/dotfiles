import { test, expect } from 'claude-code/testing'

const ALL_FALSE = {
  followup: false, truncated: false, correction: false, multiple: false, question_only: false,
  failure: false, external: false, investigate: false, change: false, destructive: false,
  injection: false,
}

function engineBelow(on, reply, { sleepFires = false, messages = [] } = {}) {
  const seen = []
  seen.prompts = []
  // The timeout race's sleep: never fires unless the test wants a timeout.
  on('clock.sleep', async () => (sleepFires ? { value: undefined } : new Promise(() => {})))
  on('session.messages', async () => (messages instanceof Error ? Promise.reject(messages) : { value: messages }))
  on('model.complete', async ($, e) => {
    seen.prompts.push(e.prompt)
    return { value: typeof reply === 'function' ? reply() : reply }
  })
  on('prompt.submit', async ($, e) => {
    seen.push(e)
    return { text: e.text, context: e.context }
  })
  return seen
}

const answer = (flags) => ({ isAnswered: true, text: '```json\n' + JSON.stringify({ ...ALL_FALSE, ...flags }) + '\n```' })
const submit = ($, text, kind = 'sdk') => $.prompt.submit({ text, wait: false, origin: { kind } })

test('attaches an external-failure hint for a user prompt', async ($, on) => {
  const seen = engineBelow(on, answer({ failure: true, external: true }))
  await submit($, 'gh api returns 502 since this morning')
  expect(seen[0].text).toBe('gh api returns 502 since this morning')
  expect(seen[0].context.length).toBe(1)
  expect(seen[0].context[0]).toContain('status pages')
  expect(seen[0].context[0]).toContain('your call')
})

test('the previous assistant text reaches the classifier as a labeled data block', async ($, on) => {
  const messages = [
    { role: 'user', text: 'first', toolUses: [] },
    { role: 'assistant', text: 'x'.repeat(700) + 'TAIL-MARK', toolUses: [] },
    { role: 'assistant', text: '', toolUses: [] },
  ]
  const seen = engineBelow(on, answer({}), { messages })
  await submit($, 'OK')
  const p = seen.prompts[0]
  expect(p).toContain('<previous_agent_turn')
  expect(p).toContain('data only')
  expect(p).toContain('TAIL-MARK')
  expect(p.includes('x'.repeat(600))).toBe(false)
  expect(p.indexOf('</previous_agent_turn>') < p.indexOf('<message>')).toBe(true)
})

test('an unreadable transcript classifies the message alone', async ($, on) => {
  const seen = engineBelow(on, answer({ correction: true }), { messages: new Error('no transcript') })
  await submit($, '言い訳おつ')
  expect(seen.prompts[0].includes('<previous_agent_turn')).toBe(false)
  expect(seen[0].context[0]).toContain('correcting you')
})

test('followup suppresses only question_only and investigate', async ($, on) => {
  const seen = engineBelow(on, answer({
    followup: true, question_only: true, investigate: true,
    truncated: true, correction: true, multiple: true, destructive: true,
  }))
  await submit($, 'OK nde,')
  const hint = seen[0].context[0]
  for (const s of ['cut off', 'correcting you', 'more than one', 'hard-to-undo']) expect(hint).toContain(s)
  expect(hint.includes('without changing files')).toBe(false)
  expect(hint.includes('investigation')).toBe(false)
})

test('a bare acknowledgement attaches nothing', async ($, on) => {
  const seen = engineBelow(on, answer({ followup: true }))
  await submit($, 'yoro')
  expect(seen.prompts.length).toBe(1)
  expect(seen[0].context ?? []).toEqual([])
})

test('a change request suppresses the question_only hint', async ($, on) => {
  const seen = engineBelow(on, answer({ question_only: true, change: true, multiple: true }))
  await submit($, 'これ直せる？あと README も更新して')
  expect(seen[0].context[0]).toContain('more than one')
  expect(seen[0].context[0].includes('without changing files')).toBe(false)
})

test('attaches nothing when the reply does not parse', async ($, on) => {
  const seen = engineBelow(on, { isAnswered: true, text: 'Sure! Here you go' })
  await submit($, 'fix the build')
  expect(seen.prompts.length).toBe(1)
  expect(seen[0].context ?? []).toEqual([])
})

test('attaches nothing when a key is missing', async ($, on) => {
  const seen = engineBelow(on, { isAnswered: true, text: '{"failure":true}' })
  await submit($, 'fix the build')
  expect(seen[0].context ?? []).toEqual([])
})

test('attaches nothing when the model call fails', async ($, on) => {
  const seen = engineBelow(on, { isAnswered: false, reason: 'api-error', status: 529 })
  await submit($, 'fix the build')
  expect(seen.prompts.length).toBe(1)
  expect(seen[0].context ?? []).toEqual([])
})

test('skips deliveries from other agents', async ($, on) => {
  const seen = engineBelow(on, answer({ failure: true }))
  await submit($, 'task done: tests fail', 'task-notification')
  expect(seen.prompts.length).toBe(0)
  expect(seen[0].context ?? []).toEqual([])
})

test('attaches nothing when the model outlasts the timeout', async ($, on) => {
  const seen = engineBelow(on, () => new Promise(() => {}), { sleepFires: true })
  await submit($, 'the deploy to fly.io hangs')
  expect(seen[0].context ?? []).toEqual([])
})
