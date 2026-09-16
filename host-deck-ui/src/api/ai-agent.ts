import { handleAccessUnauthorized, http } from '@/lib/http'
import { consumeServerSentEvents } from '@/lib/sse'

export interface AiAgentSettings {
  baseUrl: string
  model: string
  hasApiKey: boolean
}

export interface AiAgentSettingsUpdate {
  baseUrl?: string
  model?: string
  apiKey?: string
  clearApiKey?: boolean
}

export interface AiAgentSkill {
  id: string
  name: string
  description: string
  source: string
}

export interface AiAgentMcpServer {
  id: number
  name: string
  url: string
  enabled: boolean
  hasHeaders: boolean
}

export interface AiAgentMcpServerInput {
  name: string
  url: string
  enabled: boolean
  headers?: Record<string, string>
  clearHeaders?: boolean
}

export interface AiAgentConversation {
  id: string
  title?: string
  createdAt: number | string
  updatedAt: number | string
}

export type AiAgentMessageRole = 'assistant' | 'system' | 'tool' | 'user'

export interface AiAgentMessage {
  id: string
  role: AiAgentMessageRole
  content: string
  createdAt: number | string
}

export interface AiAgentConversationDetail {
  conversation: AiAgentConversation
  messages: AiAgentMessage[]
}

export interface AiAgentUsage {
  inputTokens?: number
  outputTokens?: number
  promptTokens?: number
  responseTokens?: number
  totalTokens?: number
}

export type AiAgentRunEvent =
  | { event: 'connected'; runId: string }
  | { event: 'message-delta'; messageId: string; text: string }
  | { event: 'tool-start'; callId: string; name: string; summary: string }
  | {
      event: 'approval-required'
      callId: string
      name: string
      summary: string
      arguments: unknown
    }
  | {
      event: 'tool-result'
      callId: string
      name: string
      success: boolean
      summary: string
    }
  | { event: 'usage'; usage: AiAgentUsage }
  | { event: 'done'; conversationId: string; messageId: string }
  | { event: 'error'; message: string }

export class AiAgentStreamHttpError extends Error {
  readonly status: number

  constructor(message: string, status: number) {
    super(message)
    this.name = 'AiAgentStreamHttpError'
    this.status = status
  }
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null
}

function requiredString(data: Record<string, unknown>, key: string) {
  const value = data[key]
  if (typeof value !== 'string') throw new Error(`AI Agent 事件缺少字段 ${key}。`)
  return value
}

function parseRunEvent(event: string, rawData: string): AiAgentRunEvent | null {
  if (
    ![
      'connected',
      'message-delta',
      'tool-start',
      'approval-required',
      'tool-result',
      'usage',
      'done',
      'error',
    ].includes(event)
  ) {
    return null
  }

  let parsed: unknown
  try {
    parsed = JSON.parse(rawData) as unknown
  } catch {
    throw new Error(`AI Agent 返回了无法解析的 ${event} 事件。`)
  }
  const data = asRecord(parsed)
  if (!data) throw new Error(`AI Agent 返回了无效的 ${event} 事件。`)

  switch (event) {
    case 'connected':
      return { event, runId: requiredString(data, 'runId') }
    case 'message-delta':
      return {
        event,
        messageId: requiredString(data, 'messageId'),
        text: requiredString(data, 'text'),
      }
    case 'tool-start':
      return {
        event,
        callId: requiredString(data, 'callId'),
        name: requiredString(data, 'name'),
        summary: requiredString(data, 'summary'),
      }
    case 'approval-required':
      return {
        event,
        arguments: data.arguments,
        callId: requiredString(data, 'callId'),
        name: requiredString(data, 'name'),
        summary: requiredString(data, 'summary'),
      }
    case 'tool-result':
      if (typeof data.success !== 'boolean') {
        throw new Error('AI Agent 事件缺少字段 success。')
      }
      return {
        event,
        callId: requiredString(data, 'callId'),
        name: requiredString(data, 'name'),
        success: data.success,
        summary: requiredString(data, 'summary'),
      }
    case 'usage': {
      const usage = asRecord(data.usage) ?? data
      const readTokenCount = (key: string) =>
        typeof usage[key] === 'number' ? (usage[key] as number) : undefined
      return {
        event,
        usage: {
          inputTokens: readTokenCount('inputTokens') ?? readTokenCount('promptTokens'),
          outputTokens: readTokenCount('outputTokens') ?? readTokenCount('responseTokens'),
          promptTokens: readTokenCount('promptTokens'),
          responseTokens: readTokenCount('responseTokens'),
          totalTokens: readTokenCount('totalTokens'),
        },
      }
    }
    case 'done':
      return {
        event,
        conversationId: requiredString(data, 'conversationId'),
        messageId: requiredString(data, 'messageId'),
      }
    case 'error':
      return { event, message: requiredString(data, 'message') }
    default:
      return null
  }
}

async function responseErrorMessage(response: Response) {
  const body = await response.text()
  try {
    const parsed = asRecord(JSON.parse(body) as unknown)
    return (typeof parsed?.message === 'string' && parsed.message) || body
  } catch {
    return body
  }
}

export const aiAgentApi = {
  async getSettings() {
    return (await http.get<AiAgentSettings>('/api/ai-agent/settings')).data
  },

  async saveSettings(payload: AiAgentSettingsUpdate) {
    return (await http.put<AiAgentSettings>('/api/ai-agent/settings', payload)).data
  },

  async testSettings(payload?: AiAgentSettingsUpdate) {
    return (await http.post<unknown>('/api/ai-agent/settings/test', payload ?? {})).data
  },

  async listSkills(connectionId: string) {
    return (
      await http.get<AiAgentSkill[]>('/api/ai-agent/skills', {
        params: { connectionId },
      })
    ).data
  },

  async closeSession(connectionId: string) {
    await http.delete('/api/ai-agent/session', { params: { connectionId } })
  },

  async listMcpServers() {
    return (await http.get<AiAgentMcpServer[]>('/api/ai-agent/mcp-servers')).data
  },

  async createMcpServer(payload: AiAgentMcpServerInput) {
    return (await http.post<AiAgentMcpServer>('/api/ai-agent/mcp-servers', payload)).data
  },

  async updateMcpServer(id: number, payload: AiAgentMcpServerInput) {
    return (await http.put<AiAgentMcpServer>(`/api/ai-agent/mcp-servers/${id}`, payload)).data
  },

  async deleteMcpServer(id: number) {
    await http.delete(`/api/ai-agent/mcp-servers/${id}`)
  },

  async testMcpServer(id: number) {
    return (
      await http.post<{ success: boolean; toolCount: number }>(
        `/api/ai-agent/mcp-servers/${id}/test`,
      )
    ).data
  },

  async listConversations(connectionId: string) {
    return (
      await http.get<AiAgentConversation[]>('/api/ai-agent/conversations', {
        params: { connectionId },
      })
    ).data
  },

  async createConversation(connectionId: string) {
    return (await http.post<AiAgentConversation>('/api/ai-agent/conversations', { connectionId }))
      .data
  },

  async getConversation(id: string, connectionId: string) {
    return (
      await http.get<AiAgentConversationDetail>(
        `/api/ai-agent/conversations/${encodeURIComponent(id)}`,
        { params: { connectionId } },
      )
    ).data
  },

  async updateConversation(id: string, connectionId: string, title: string) {
    return (
      await http.put<AiAgentConversation>(`/api/ai-agent/conversations/${encodeURIComponent(id)}`, {
        connectionId,
        title,
      })
    ).data
  },

  async deleteConversation(id: string, connectionId: string) {
    await http.delete(`/api/ai-agent/conversations/${encodeURIComponent(id)}`, {
      params: { connectionId },
    })
  },

  async run(
    conversationId: string,
    connectionId: string,
    input: string,
    skillIds: string[],
    onEvent: (event: AiAgentRunEvent) => void,
    signal?: AbortSignal,
  ) {
    const response = await fetch(
      `/api/ai-agent/conversations/${encodeURIComponent(conversationId)}/runs`,
      {
        body: JSON.stringify({ connectionId, input, skillIds }),
        credentials: 'same-origin',
        headers: { Accept: 'text/event-stream', 'Content-Type': 'application/json' },
        method: 'POST',
        signal,
      },
    )
    if (!response.ok) {
      if (response.status === 401) handleAccessUnauthorized()
      const message =
        (await responseErrorMessage(response)) || `启动 AI Agent 失败 (${response.status})`
      throw new AiAgentStreamHttpError(message, response.status)
    }
    if (!response.headers.get('content-type')?.includes('text/event-stream')) {
      throw new Error((await responseErrorMessage(response)) || 'AI Agent 未返回流式响应。')
    }
    if (!response.body) throw new Error('浏览器未提供 AI Agent 流式响应。')

    let completed = false
    await consumeServerSentEvents(response.body, (message) => {
      const parsed = parseRunEvent(message.event, message.data)
      if (!parsed) return
      if (parsed.event === 'error') throw new Error(parsed.message)
      if (parsed.event === 'done') completed = true
      onEvent(parsed)
    })

    if (!completed && !signal?.aborted) {
      throw new Error('AI Agent 响应意外中断。')
    }
  },

  async approve(runId: string, callId: string) {
    return (await http.post(`/api/ai-agent/runs/${encodeURIComponent(runId)}/approve`, { callId }))
      .data
  },

  async reject(runId: string, callId: string) {
    return (await http.post(`/api/ai-agent/runs/${encodeURIComponent(runId)}/reject`, { callId }))
      .data
  },

  async cancel(runId: string) {
    await http.delete(`/api/ai-agent/runs/${encodeURIComponent(runId)}`)
  },
}
