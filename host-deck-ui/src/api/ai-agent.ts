import { handleAccessUnauthorized, http } from '@/lib/http'
import { consumeServerSentEvents } from '@/lib/sse'

export interface AiAgentModelConfig {
  id: string
  name: string
}

export interface AiAgentSettings {
  baseUrl: string
  model: string
  models: AiAgentModelConfig[]
  hasApiKey: boolean
  showRemoteSkills: boolean
}

export interface AiAgentSettingsUpdate {
  baseUrl?: string
  model?: string
  models?: AiAgentModelConfig[]
  apiKey?: string
  clearApiKey?: boolean
  showRemoteSkills?: boolean
}

export interface AiAgentSkill {
  id: string
  name: string
  description: string
  source: string
  editable: boolean
}

export interface AiAgentSkillDetail extends AiAgentSkill {
  content: string
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

export type AiAgentMessageRole = 'assistant' | 'error' | 'system' | 'tool' | 'user'

export interface AiAgentImageAttachment {
  name: string
  mimeType: string
  data: string
}

export interface AiAgentMessageToolCall {
  id: string
  name: string
  arguments?: unknown
  summary?: string
}

export interface AiAgentMessage {
  id: string
  role: AiAgentMessageRole
  content: string
  attachments: AiAgentImageAttachment[]
  toolCallId?: string
  toolCalls?: AiAgentMessageToolCall[]
  toolStatus?: 'success' | 'failed' | 'rejected' | 'expired' | 'cancelled'
  toolResult?: AiAgentToolResult
  usage?: AiAgentUsage
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

export type AiAgentRunMode = 'chat' | 'agent'

export type AiAgentRunStepType = 'model' | 'tool' | 'approval' | 'message' | 'error' | 'summary'
export type AiAgentRunStepStatus =
  | 'queued'
  | 'running'
  | 'waiting-approval'
  | 'success'
  | 'failed'
  | 'rejected'
  | 'cancelled'
  | 'expired'

export type AiAgentRunStatus = 'success' | 'failed' | 'cancelled' | 'expired'

export interface AiAgentRunStep {
  runId: string
  stepId: string
  parentStepId?: string
  sequence: number
  type: AiAgentRunStepType
  status: AiAgentRunStepStatus
  startedAt: number | string
  completedAt?: number | string
  messageId?: string
  callId?: string
  name?: string
  summary?: string
  arguments?: unknown
  content?: string
  restored?: boolean
}

export interface AiAgentToolCallRecord {
  callId: string
  stepId: string
  name: string
  arguments?: unknown
  summary: string
  status: AiAgentRunStepStatus
}

export interface AiAgentToolResult {
  content: string
  exitCode?: number
  stderr?: string
  durationMs?: number
  truncated?: boolean
  path?: string
  operation?: 'read' | 'write' | 'patch' | string
  diff?: string
  changed?: boolean
  structured?: unknown
  mcpServer?: string
  mcpTool?: string
}

interface AiAgentRunEventMeta {
  runId?: string
  sequence?: number
  stepId?: string
  parentStepId?: string
  type?: AiAgentRunStepType
  status?: AiAgentRunStepStatus
  startedAt?: number | string
  completedAt?: number | string
}

export type AiAgentRunEvent =
  | ({ event: 'connected'; runId: string } & AiAgentRunEventMeta)
  | ({ event: 'model-start'; messageId: string } & AiAgentRunEventMeta)
  | ({ event: 'model-end'; messageId: string } & AiAgentRunEventMeta)
  | ({ event: 'message-delta'; messageId: string; text: string } & AiAgentRunEventMeta)
  | ({ event: 'message-reset'; messageId: string } & AiAgentRunEventMeta)
  | ({
      event: 'tool-start'
      callId: string
      name: string
      summary: string
      arguments?: unknown
    } & AiAgentRunEventMeta)
  | ({
      event: 'approval-required'
      callId: string
      name: string
      summary: string
      arguments: unknown
    } & AiAgentRunEventMeta)
  | ({
      event: 'tool-result'
      callId: string
      name: string
      success: boolean
      summary: string
      result?: AiAgentToolResult
    } & AiAgentRunEventMeta)
  | ({ event: 'usage'; usage: AiAgentUsage } & AiAgentRunEventMeta)
  | ({ event: 'done'; conversationId: string; messageId: string } & AiAgentRunEventMeta)
  | ({ event: 'error'; message: string } & AiAgentRunEventMeta)
  | ({
      event: 'run-end'
      status: AiAgentRunStatus
      durationMs?: number
      message?: string
      code?: string
    } & AiAgentRunEventMeta)

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

function meta(data: Record<string, unknown>): AiAgentRunEventMeta {
  const result: AiAgentRunEventMeta = {}
  for (const key of ['runId', 'stepId', 'parentStepId'] as const) {
    const value = data[key]
    if (typeof value === 'string') result[key] = value
  }
  for (const key of ['startedAt', 'completedAt'] as const) {
    const value = data[key]
    if (typeof value === 'string' || typeof value === 'number') result[key] = value
  }
  if (typeof data.sequence === 'number') result.sequence = data.sequence
  if (typeof data.type === 'string') result.type = data.type as AiAgentRunStepType
  if (typeof data.status === 'string') result.status = data.status as AiAgentRunStepStatus
  return result
}

function parseRunEvent(event: string, rawData: string): AiAgentRunEvent | null {
  if (
    ![
      'connected',
      'model-start',
      'model-end',
      'message-delta',
      'message-reset',
      'tool-start',
      'approval-required',
      'tool-result',
      'usage',
      'done',
      'error',
      'run-end',
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
      return { ...meta(data), event, runId: requiredString(data, 'runId') }
    case 'model-start':
      return { ...meta(data), event, messageId: requiredString(data, 'messageId') }
    case 'model-end':
      return { ...meta(data), event, messageId: requiredString(data, 'messageId') }
    case 'message-delta':
      return {
        ...meta(data),
        event,
        messageId: requiredString(data, 'messageId'),
        text: requiredString(data, 'text'),
      }
    case 'message-reset':
      return {
        ...meta(data),
        event,
        messageId: requiredString(data, 'messageId'),
      }
    case 'tool-start':
      return {
        ...meta(data),
        event,
        callId: requiredString(data, 'callId'),
        name: requiredString(data, 'name'),
        summary: requiredString(data, 'summary'),
        ...(data.arguments !== undefined ? { arguments: data.arguments } : {}),
      }
    case 'approval-required':
      return {
        ...meta(data),
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
        ...meta(data),
        event,
        callId: requiredString(data, 'callId'),
        name: requiredString(data, 'name'),
        success: data.success,
        summary: requiredString(data, 'summary'),
        ...(data.content !== undefined
          ? {
              result: {
                content:
                  typeof data.content === 'string' ? data.content : JSON.stringify(data.content),
                ...(typeof data.exitCode === 'number' ? { exitCode: data.exitCode } : {}),
                ...(typeof data.stderr === 'string' ? { stderr: data.stderr } : {}),
                ...(typeof data.durationMs === 'number' ? { durationMs: data.durationMs } : {}),
                ...(typeof data.truncated === 'boolean' ? { truncated: data.truncated } : {}),
                ...(typeof data.path === 'string' ? { path: data.path } : {}),
                ...(typeof data.operation === 'string' ? { operation: data.operation } : {}),
                ...(typeof data.diff === 'string' ? { diff: data.diff } : {}),
                ...(typeof data.changed === 'boolean' ? { changed: data.changed } : {}),
                ...(data.structured !== undefined ? { structured: data.structured } : {}),
                ...(typeof data.mcpServer === 'string' ? { mcpServer: data.mcpServer } : {}),
                ...(typeof data.mcpTool === 'string' ? { mcpTool: data.mcpTool } : {}),
              },
            }
          : {}),
      }
    case 'usage': {
      const usage = asRecord(data.usage) ?? data
      const readTokenCount = (key: string) =>
        typeof usage[key] === 'number' ? (usage[key] as number) : undefined
      return {
        event,
        ...meta(data),
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
        ...meta(data),
        conversationId: requiredString(data, 'conversationId'),
        messageId: requiredString(data, 'messageId'),
      }
    case 'error':
      return {
        ...meta(data),
        event,
        message: requiredString(data, 'message'),
        ...(typeof data.code === 'string' ? { code: data.code } : {}),
      }
    case 'run-end': {
      const status = data.status
      if (
        status !== 'success' &&
        status !== 'failed' &&
        status !== 'cancelled' &&
        status !== 'expired'
      ) {
        throw new Error('AI Agent 事件缺少有效的运行状态。')
      }
      return {
        ...meta(data),
        event,
        status,
        ...(typeof data.durationMs === 'number' ? { durationMs: data.durationMs } : {}),
        ...(typeof data.message === 'string' ? { message: data.message } : {}),
        ...(typeof data.code === 'string' ? { code: data.code } : {}),
      }
    }
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

  async listModels() {
    return (await http.get<string[]>('/api/ai-agent/models')).data
  },

  async listSkills(connectionId: string) {
    return (
      await http.get<AiAgentSkill[]>('/api/ai-agent/skills', {
        params: { connectionId },
      })
    ).data
  },

  async listManagedSkills() {
    return (await http.get<AiAgentSkill[]>('/api/ai-agent/skills/library')).data
  },

  async createManagedSkill(content: string) {
    return (await http.post<AiAgentSkillDetail>('/api/ai-agent/skills', { content })).data
  },

  async getManagedSkill(id: number) {
    return (await http.get<AiAgentSkillDetail>(`/api/ai-agent/skills/${id}`)).data
  },

  async updateManagedSkill(id: number, content: string) {
    return (await http.put<AiAgentSkillDetail>(`/api/ai-agent/skills/${id}`, { content })).data
  },

  async deleteManagedSkill(id: number) {
    await http.delete(`/api/ai-agent/skills/${id}`)
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
    model?: string,
    attachments: AiAgentImageAttachment[] = [],
    mode: AiAgentRunMode = 'agent',
  ) {
    const response = await fetch(
      `/api/ai-agent/conversations/${encodeURIComponent(conversationId)}/runs`,
      {
        body: JSON.stringify({
          connectionId,
          input,
          mode,
          ...(model ? { model } : {}),
          skillIds,
          ...(attachments.length ? { attachments } : {}),
        }),
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
    let streamError: Error | null = null
    await consumeServerSentEvents(response.body, (message) => {
      const parsed = parseRunEvent(message.event, message.data)
      if (!parsed) return
      if (parsed.event === 'error') {
        streamError = new Error(parsed.message)
      }
      if (parsed.event === 'done' || (parsed.event === 'run-end' && parsed.status === 'success')) {
        completed = true
      }
      onEvent(parsed)
    })

    if (streamError) throw streamError
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
