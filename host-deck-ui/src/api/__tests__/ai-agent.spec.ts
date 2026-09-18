import { afterEach, describe, expect, it, vi } from 'vitest'
import { aiAgentApi, AiAgentStreamHttpError } from '@/api/ai-agent'
import { http } from '@/lib/http'

afterEach(() => {
  vi.restoreAllMocks()
  vi.unstubAllGlobals()
})

describe('aiAgentApi skills', () => {
  it('lists skills for the active connection', async () => {
    const skills = [{ description: 'Inspect logs', id: 'logs', name: 'Logs', source: 'workspace' }]
    const get = vi.spyOn(http, 'get').mockResolvedValue({ data: skills })

    await expect(aiAgentApi.listSkills('connection-1')).resolves.toEqual(skills)
    expect(get).toHaveBeenCalledWith('/api/ai-agent/skills', {
      params: { connectionId: 'connection-1' },
    })
  })

  it('closes the shared session for the active connection', async () => {
    const remove = vi.spyOn(http, 'delete').mockResolvedValue({ data: { success: true } })

    await aiAgentApi.closeSession('connection-1')

    expect(remove).toHaveBeenCalledWith('/api/ai-agent/session', {
      params: { connectionId: 'connection-1' },
    })
  })
})

describe('aiAgentApi MCP servers', () => {
  it('manages and tests Streamable HTTP servers', async () => {
    const server = {
      enabled: true,
      hasHeaders: true,
      id: 7,
      name: 'GitHub',
      url: 'https://mcp.example.com/mcp',
    }
    const get = vi.spyOn(http, 'get').mockResolvedValue({ data: [server] })
    const post = vi
      .spyOn(http, 'post')
      .mockResolvedValueOnce({ data: server })
      .mockResolvedValueOnce({ data: { success: true, toolCount: 4 } })
    const put = vi.spyOn(http, 'put').mockResolvedValue({ data: { ...server, enabled: false } })
    const remove = vi.spyOn(http, 'delete').mockResolvedValue({ data: undefined })
    const payload = {
      enabled: true,
      headers: { Authorization: 'Bearer secret' },
      name: 'GitHub',
      url: 'https://mcp.example.com/mcp',
    }

    await expect(aiAgentApi.listMcpServers()).resolves.toEqual([server])
    await expect(aiAgentApi.createMcpServer(payload)).resolves.toEqual(server)
    await expect(
      aiAgentApi.updateMcpServer(7, { ...payload, enabled: false }),
    ).resolves.toMatchObject({ enabled: false })
    await expect(aiAgentApi.testMcpServer(7)).resolves.toEqual({ success: true, toolCount: 4 })
    await aiAgentApi.deleteMcpServer(7)

    expect(get).toHaveBeenCalledWith('/api/ai-agent/mcp-servers')
    expect(post).toHaveBeenNthCalledWith(1, '/api/ai-agent/mcp-servers', payload)
    expect(put).toHaveBeenCalledWith('/api/ai-agent/mcp-servers/7', {
      ...payload,
      enabled: false,
    })
    expect(post).toHaveBeenNthCalledWith(2, '/api/ai-agent/mcp-servers/7/test')
    expect(remove).toHaveBeenCalledWith('/api/ai-agent/mcp-servers/7')
  })
})

describe('aiAgentApi.run', () => {
  it('consumes the complete run lifecycle with same-origin credentials', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(
        new Response(
          'event: connected\ndata: {"runId":"run-1"}\n\n' +
            'event: message-delta\ndata: {"messageId":"message-1","text":"hello"}\n\n' +
            'event: tool-start\ndata: {"callId":"call-1","name":"shell","summary":"Inspect files"}\n\n' +
            'event: approval-required\ndata: {"callId":"call-1","name":"shell","summary":"Remove file","arguments":{"command":"rm old"}}\n\n' +
             'event: tool-result\ndata: {"callId":"call-1","name":"shell","success":true,"summary":"Done","content":"ok","exitCode":0,"durationMs":12,"truncated":false}\n\n' +
            'event: usage\ndata: {"inputTokens":10,"outputTokens":5,"totalTokens":15}\n\n' +
            'event: done\ndata: {"conversationId":"conversation-1","messageId":"message-1"}\n\n',
          { headers: { 'Content-Type': 'text/event-stream' } },
        ),
      )
    vi.stubGlobal('fetch', fetchMock)
    const events: unknown[] = []

    await aiAgentApi.run(
      'conversation-1',
      'connection-1',
      'hello',
      ['logs'],
      (event) => events.push(event),
      undefined,
      'gpt-5',
      [{ data: 'aGVsbG8=', mimeType: 'image/png', name: 'screen.png' }],
    )

    expect(fetchMock).toHaveBeenCalledWith(
      '/api/ai-agent/conversations/conversation-1/runs',
      expect.objectContaining({
        body: JSON.stringify({
          connectionId: 'connection-1',
          input: 'hello',
          mode: 'agent',
          model: 'gpt-5',
          skillIds: ['logs'],
          attachments: [{ data: 'aGVsbG8=', mimeType: 'image/png', name: 'screen.png' }],
        }),
        credentials: 'same-origin',
        method: 'POST',
      }),
    )
    expect(events).toHaveLength(7)
    expect(events[3]).toMatchObject({
      arguments: { command: 'rm old' },
      callId: 'call-1',
      event: 'approval-required',
    })
    expect(events[4]).toMatchObject({
      result: { content: 'ok', durationMs: 12, exitCode: 0, truncated: false },
    })
    expect(events.at(-1)).toEqual({
      conversationId: 'conversation-1',
      event: 'done',
      messageId: 'message-1',
    })
  })

  it('rejects malformed events and streams that end before done', async () => {
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockResolvedValueOnce(
          new Response('event: message-delta\ndata: {not-json}\n\n', {
            headers: { 'Content-Type': 'text/event-stream' },
            status: 200,
          }),
        )
        .mockResolvedValueOnce(
          new Response('event: connected\ndata: {"runId":"run-1"}\n\n', {
            headers: { 'Content-Type': 'text/event-stream' },
            status: 200,
          }),
        ),
    )

    await expect(
      aiAgentApi.run('conversation-1', 'connection-1', 'hello', [], () => undefined),
    ).rejects.toThrow('无法解析')
    await expect(
      aiAgentApi.run('conversation-1', 'connection-1', 'hello', [], () => undefined),
    ).rejects.toThrow('意外中断')
  })

  it('cancels the response stream when event parsing fails', async () => {
    let cancelled = false
    const stream = new ReadableStream<Uint8Array>({
      cancel() {
        cancelled = true
      },
      start(controller) {
        controller.enqueue(new TextEncoder().encode('event: message-delta\ndata: {not-json}\n\n'))
      },
    })
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response(stream, {
          headers: { 'Content-Type': 'text/event-stream' },
          status: 200,
        }),
      ),
    )

    await expect(
      aiAgentApi.run('conversation-1', 'connection-1', 'hello', [], () => undefined),
    ).rejects.toThrow('无法解析')
    expect(cancelled).toBe(true)
  })

  it('surfaces a business error returned as a JSON response', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response('{"code":400,"message":"API key is not configured."}', {
          headers: { 'Content-Type': 'application/json' },
          status: 200,
        }),
      ),
    )

    await expect(
      aiAgentApi.run('conversation-1', 'connection-1', 'hello', [], () => undefined),
    ).rejects.toThrow('API key is not configured.')
  })

  it('surfaces HTTP errors and passes the AbortSignal to fetch', async () => {
    const controller = new AbortController()
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response('{"message":"bad configuration"}', { status: 422 }))
      .mockRejectedValueOnce(new DOMException('Aborted', 'AbortError'))
    vi.stubGlobal('fetch', fetchMock)

    await expect(
      aiAgentApi.run('conversation-1', 'connection-1', 'hello', [], () => undefined),
    ).rejects.toEqual(expect.objectContaining<Partial<AiAgentStreamHttpError>>({ status: 422 }))

    controller.abort()
    await expect(
      aiAgentApi.run(
        'conversation-1',
        'connection-1',
        'hello',
        [],
        () => undefined,
        controller.signal,
      ),
    ).rejects.toMatchObject({ name: 'AbortError' })
    expect(fetchMock.mock.calls[1]?.[1]).toEqual(
      expect.objectContaining({ signal: controller.signal }),
    )
  })
})
