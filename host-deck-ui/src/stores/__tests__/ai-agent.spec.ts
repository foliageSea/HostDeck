import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { AiAgentRunEvent } from '@/api/ai-agent'
import { useAiAgentStore } from '@/stores/ai-agent'

const apiMocks = vi.hoisted(() => ({
  approve: vi.fn(),
  cancel: vi.fn(),
  createConversation: vi.fn(),
  deleteConversation: vi.fn(),
  getConversation: vi.fn(),
  getSettings: vi.fn(),
  listConversations: vi.fn(),
  reject: vi.fn(),
  run: vi.fn(),
  saveSettings: vi.fn(),
  testSettings: vi.fn(),
}))

vi.mock('@/api/ai-agent', () => ({ aiAgentApi: apiMocks }))

const conversation = {
  createdAt: 1,
  id: 'conversation-1',
  title: 'Maintain host',
  updatedAt: 1,
}

describe('AI Agent store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.clearAllMocks()
    apiMocks.createConversation.mockResolvedValue(conversation)
    apiMocks.listConversations.mockResolvedValue([conversation])
    apiMocks.approve.mockResolvedValue(undefined)
    apiMocks.cancel.mockResolvedValue(undefined)
    apiMocks.reject.mockResolvedValue(undefined)
  })

  it('applies incremental deltas and resolves an approval while the run stays open', async () => {
    let releaseRun!: () => void
    const runFinished = new Promise<void>((resolve) => (releaseRun = resolve))
    apiMocks.run.mockImplementation(
      async (
        _conversationId: string,
        _connectionId: string,
        _input: string,
        onEvent: (event: AiAgentRunEvent) => void,
      ) => {
        onEvent({ event: 'connected', runId: 'run-1' })
        onEvent({ event: 'message-delta', messageId: 'message-1', text: 'First ' })
        onEvent({ event: 'message-delta', messageId: 'message-1', text: 'second' })
        onEvent({
          arguments: { command: 'uptime' },
          callId: 'call-1',
          event: 'approval-required',
          name: 'shell',
          summary: 'Run uptime',
        })
        await runFinished
        onEvent({ conversationId: 'conversation-1', event: 'done', messageId: 'message-1' })
      },
    )
    const store = useAiAgentStore()

    const activeRun = store.startRun('inspect host', 'connection-1')
    await vi.waitFor(() => expect(store.activeRunId).toBe('run-1'))

    expect(store.messages.map((message) => message.content)).toEqual([
      'inspect host',
      'First second',
    ])
    expect(store.toolCalls[0]).toMatchObject({
      approvalPending: true,
      arguments: { command: 'uptime' },
      status: 'pending',
    })

    await store.resolveApproval('call-1', true)
    expect(apiMocks.approve).toHaveBeenCalledWith('run-1', 'call-1')
    expect(store.toolCalls[0]).toMatchObject({ approvalPending: false, status: 'running' })

    releaseRun()
    await activeRun
    expect(store.running).toBe(false)
    expect(store.messages.at(-1)?.id).toBe('message-1')
  })

  it('ignores stale conversation detail responses after the connection changes', async () => {
    let resolveDetail!: (value: { conversation: typeof conversation; messages: [] }) => void
    apiMocks.getConversation.mockReturnValue(
      new Promise((resolve) => {
        resolveDetail = resolve
      }),
    )
    const store = useAiAgentStore()

    const detail = store.selectConversation('conversation-1', 'connection-1')
    store.resetForConnection('connection-2')
    resolveDetail({ conversation, messages: [] })
    await detail

    expect(store.currentConnectionId).toBe('connection-2')
    expect(store.selectedConversation).toBeNull()
  })

  it('does not overwrite a completed tool when approval responds late', async () => {
    let emit!: (event: AiAgentRunEvent) => void
    let finishRun!: () => void
    let finishApproval!: () => void
    apiMocks.run.mockImplementation(
      async (
        _conversationId: string,
        _connectionId: string,
        _input: string,
        onEvent: (event: AiAgentRunEvent) => void,
      ) => {
        emit = onEvent
        onEvent({ event: 'connected', runId: 'run-1' })
        onEvent({
          arguments: { command: 'uptime' },
          callId: 'call-1',
          event: 'approval-required',
          name: 'shell_execute',
          summary: 'Run uptime',
        })
        await new Promise<void>((resolve) => (finishRun = resolve))
        onEvent({ conversationId: 'conversation-1', event: 'done', messageId: 'message-1' })
      },
    )
    apiMocks.approve.mockImplementation(
      () => new Promise<void>((resolve) => (finishApproval = resolve)),
    )
    const store = useAiAgentStore()
    const run = store.startRun('inspect host', 'connection-1')
    await vi.waitFor(() => expect(store.activeRunId).toBe('run-1'))

    const approval = store.resolveApproval('call-1', true)
    await vi.waitFor(() => expect(apiMocks.approve).toHaveBeenCalled())
    emit({
      callId: 'call-1',
      event: 'tool-result',
      name: 'shell_execute',
      success: true,
      summary: 'Completed',
    })
    finishApproval()
    await approval
    expect(store.toolCalls[0]?.status).toBe('success')

    finishRun()
    await run
  })

  it('terminalizes pending approvals when a run is cancelled', async () => {
    let finishRun!: () => void
    apiMocks.run.mockImplementation(
      async (
        _conversationId: string,
        _connectionId: string,
        _input: string,
        onEvent: (event: AiAgentRunEvent) => void,
      ) => {
        onEvent({ event: 'connected', runId: 'run-1' })
        onEvent({
          arguments: { path: '/etc/hosts' },
          callId: 'call-1',
          event: 'approval-required',
          name: 'file_read',
          summary: 'Read file',
        })
        await new Promise<void>((resolve) => (finishRun = resolve))
      },
    )
    const store = useAiAgentStore()
    void store.startRun('read file', 'connection-1')
    await vi.waitFor(() => expect(store.activeRunId).toBe('run-1'))

    await store.cancelRun()
    expect(store.running).toBe(false)
    expect(store.toolCalls[0]).toMatchObject({ approvalPending: false, status: 'error' })

    finishRun()
  })
})
