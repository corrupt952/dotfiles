import { test, expect } from 'claude-code/testing'

const block = (lines: string) => `Exit code 128\n<sandbox_violations>\n${lines}\n</sandbox_violations>`
const denial = 'deny network-outbound gitlab.com:443 (user denied)'
const bash = { tool: 'Bash', command: 'git ls-remote' } as const

test('adds one hint naming the denied destinations and preserves the original result', async ($, on) => {
  const text = block([denial, denial, 'deny network-outbound example.com:80'].join('\n'))
  on('tool.call', async () => ({ result: text, text, isError: true, context: ['prior'] }))
  const result = await $.tool.call(bash)
  expect(result.text).toBe(text)
  expect(result.isError).toBe(true)
  expect(result.context).toEqual(['prior', '接続できなかった宛先: gitlab.com:443, example.com:80。依頼の遂行にこの接続が必要か確認してください。'])
})

for (const [name, text, isError, input] of [
  ['ordinary permission error', 'Operation not permitted', true, bash],
  ['missing block', denial, true, bash],
  ['non-network refusal', block('deny file-write /tmp/foo'), true, bash],
  ['successful output', block(denial), false, bash],
  ['unsandboxed command', block(denial), true, { ...bash, dangerouslyDisableSandbox: true }],
  ['different tool', block(denial), true, { tool: 'Read', file_path: '/x' }],
] as const) {
  test(name, async ($, on) => {
    on('tool.call', async () => isError ? { text, result: text, isError: true } : { text, result: text })
    expect((await $.tool.call(input)).context ?? []).toEqual([])
  })
}
