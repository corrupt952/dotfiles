import type { On } from 'claude-code'

export function register(on: On) {
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const result = await next(e)
    if (!result.isError || e.dangerouslyDisableSandbox || typeof result.text !== 'string') return result

    const block = result.text.trimEnd().match(/(?:^|\n)<sandbox_violations>\n([^<>]*)\n<\/sandbox_violations>$/)
    if (!block?.[1]) return result
    const hosts = new Set<string>()
    for (const line of block[1].split('\n')) {
      const denied = /^deny network-outbound ([a-z\d.-]+:\d+|\[[a-f\d:]+\]:\d+)(?: \([^()\n]*\))?$/i.exec(line)
      if (denied?.[1]) hosts.add(denied[1])
    }
    if (!hosts.size) return result
    const hint = `接続できなかった宛先: ${[...hosts].join(', ')}。依頼の遂行にこの接続が必要か確認してください。`
    return { ...result, context: [...(result.context ?? []), hint] }
  })
}
