import { describe, expect, it } from 'vitest'
import { parseMcpConfig } from '../mcp-config'

describe('parseMcpConfig', () => {
  it('accepts a plain headers object', () => {
    expect(parseMcpConfig('{"Authorization":"Bearer token"}')).toEqual({
      headers: { Authorization: 'Bearer token' },
    })
  })

  it('extracts a complete MCP server config', () => {
    expect(
      parseMcpConfig(
        JSON.stringify({
          type: 'sse',
          url: 'https://mcp.context7.com/mcp',
          headers: { CONTEXT7_API_KEY: 'secret' },
        }),
      ),
    ).toEqual({
      headers: { CONTEXT7_API_KEY: 'secret' },
      name: 'context7',
      url: 'https://mcp.context7.com/mcp',
    })
  })

  it('rejects unrelated objects and non-string headers', () => {
    expect(() => parseMcpConfig('{"id":"Asia/Shanghai","offset":480}')).toThrow(
      '请求头必须是字符串键值组成的 JSON 对象',
    )
    expect(() => parseMcpConfig('{"url":"https://example.com/mcp","headers":{"token":1}}')).toThrow(
      '请求头必须是字符串键值组成的 JSON 对象',
    )
  })
})
