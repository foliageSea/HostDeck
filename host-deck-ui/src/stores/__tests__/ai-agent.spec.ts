import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { AiAgentRunEvent, AiAgentSettings } from '@/api/ai-agent'
import { MAX_SELECTED_SKILLS, useAiAgentStore } from '@/stores/ai-agent'

const apiMocks = vi.hoisted(() => ({
  approve: vi.fn(),
  cancel: vi.fn(),
  createConversation: vi.fn(),
  createManagedSkill: vi.fn(),
  deleteConversation: vi.fn(),
  deleteManagedSkill: vi.fn(),
  getConversation: vi.fn(),
  getManagedSkill: vi.fn(),
  getSettings: vi.fn(),
  listConversations: vi.fn(),
  listManagedSkills: vi.fn(),
  listSkills: vi.fn(),
  reject: vi.fn(),
  run: vi.fn(),
  saveSettings: vi.fn(),
  testSettings: vi.fn(),
  updateConversation: vi.fn(),
  updateManagedSkill: vi.fn(),
}))

vi.mock('@/api/ai-agent', () => ({ aiAgentApi: apiMocks }))

const conversation = {
  createdAt: 1,
  id: 'conversation-1',
  title: 'Maintain host',
  updatedAt: 1,
}

function thinkingSettings(model = 'model-a', provider = 'custom'): AiAgentSettings {
  return {
    provider,
    model,
    api: 'openai-completions',
    baseUrl: 'https://example.com/v1',
    hasApiKey: true,
    hasOAuth: false,
    hasCredentials: true,
    models: [],
    providers: [],
    showRemoteSkills: false,
  }
}

describe('AI Agent store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    window.localStorage.clear()
    vi.clearAllMocks()
    apiMocks.createConversation.mockResolvedValue(conversation)
    apiMocks.listConversations.mockResolvedValue([conversation])
    apiMocks.listSkills.mockResolvedValue([
      {
        description: 'Inspect logs',
        editable: false,
        id: 'logs',
        name: 'Logs',
        source: 'workspace',
      },
      {
        description: 'Review services',
        editable: false,
        id: 'services',
        name: 'Services',
        source: 'builtin',
      },
    ])
    apiMocks.listManagedSkills.mockResolvedValue([])
    apiMocks.approve.mockResolvedValue(undefined)
    apiMocks.cancel.mockResolvedValue(undefined)
    apiMocks.reject.mockResolvedValue(undefined)
    apiMocks.updateConversation.mockResolvedValue({
      ...conversation,
      title: 'Renamed conversation',
    })
  })

  it('persists thinking per provider/model and restores it in a new store', () => {
    const store = useAiAgentStore()
    store.settings = thinkingSettings()
    store.setThinkingLevel('high')
    store.settings = thinkingSettings('model-b')
    expect(store.thinkingLevel).toBe('default')
    store.setThinkingLevel('low')
    store.settings = thinkingSettings()
    expect(store.thinkingLevel).toBe('high')
    store.settings = thinkingSettings('model-a', 'other')
    expect(store.thinkingLevel).toBe('default')

    setActivePinia(createPinia())
    const restored = useAiAgentStore()
    restored.settings = thinkingSettings()
    expect(restored.thinkingLevel).toBe('high')
    restored.setThinkingLevel('default')
    expect(restored.thinkingLevel).toBe('default')
  })

  it('honors model thinking capabilities and rejects unsupported or in-run changes', () => {
    const store = useAiAgentStore()
    store.settings = thinkingSettings('model-a', 'openai')
    store.modelCatalog = [
      {
        id: 'openai',
        models: [
          {
            id: 'model-a',
            name: 'Model A',
            api: 'openai-responses',
            baseUrl: '',
            input: ['text'],
            reasoning: true,
            thinkingLevels: ['low', 'high', 'xhigh'],
          },
        ],
      },
    ]
    store.setThinkingLevel('xhigh')
    expect(store.thinkingLevel).toBe('xhigh')
    store.setThinkingLevel('off')
    expect(store.thinkingLevel).toBe('xhigh')
    store.running = true
    store.setThinkingLevel('low')
    expect(store.thinkingLevel).toBe('xhigh')
    store.running = false
    store.modelCatalog[0]!.models[0]!.thinkingLevels = ['off']
    expect(store.canAdjustThinking).toBe(false)
    expect(store.thinkingLevel).toBe('default')
  })

  it('passes explicit off to runs in both modes and omits reasoning after resetting', async () => {
    const store = useAiAgentStore()
    store.resetForConnection('connection-1')
    store.settings = thinkingSettings()
    store.setThinkingLevel('off')
    apiMocks.run.mockResolvedValue(undefined)
    for (const mode of ['chat', 'agent'] as const) {
      store.setRunMode(mode)
      await store.startRun('hello', 'connection-1')
      expect(apiMocks.run.mock.lastCall?.[8]).toBe(mode)
      expect(apiMocks.run.mock.lastCall?.[9]).toBe('off')
    }
    store.setThinkingLevel('default')
    await store.startRun('hello again', 'connection-1')
    expect(apiMocks.run.mock.lastCall).toHaveLength(9)
  })

  it('ignores malformed stored thinking preferences', () => {
    window.localStorage.setItem('host-deck-ui.aiAgent.thinkingLevels', '{bad')
    const store = useAiAgentStore()
    store.settings = thinkingSettings()
    expect(store.thinkingLevel).toBe('default')
  })

  it('records elapsed time at completion and clears it for a new conversation', async () => {
    const clock = vi.spyOn(performance, 'now').mockReturnValue(100)
    apiMocks.run.mockImplementation(
      async (
        _conversationId: string,
        _connectionId: string,
        _input: string,
        _skillIds: string[],
        onEvent: (event: AiAgentRunEvent) => void,
      ) => {
        clock.mockReturnValue(1350)
        onEvent({ conversationId: 'conversation-1', event: 'done', messageId: 'message-1' })
        clock.mockReturnValue(2000)
      },
    )
    try {
      const store = useAiAgentStore()
      await store.startRun('inspect host', 'connection-1')
      expect(store.durationMs).toBe(1250)
      await store.createConversation('connection-1')
      expect(store.durationMs).toBeNull()
    } finally {
      clock.mockRestore()
    }
  })

  it('does not reload the currently selected conversation', async () => {
    const store = useAiAgentStore()
    store.resetForConnection('connection-1')
    store.selectedConversation = conversation

    await store.selectConversation('conversation-1', 'connection-1')

    expect(apiMocks.getConversation).not.toHaveBeenCalled()
  })

  it('does not request another conversation while one is loading', async () => {
    let resolveConversation!: (value: { conversation: typeof conversation; messages: [] }) => void
    apiMocks.getConversation.mockReturnValue(
      new Promise((resolve) => {
        resolveConversation = resolve
      }),
    )
    const store = useAiAgentStore()

    const firstRequest = store.selectConversation('conversation-1', 'connection-1')
    await store.selectConversation('conversation-2', 'connection-1')

    expect(apiMocks.getConversation).toHaveBeenCalledTimes(1)
    expect(apiMocks.getConversation).toHaveBeenCalledWith('conversation-1', 'connection-1')

    resolveConversation({ conversation, messages: [] })
    await firstRequest
  })

  it('updates the title in both the conversation list and selected detail', async () => {
    apiMocks.getConversation.mockResolvedValue({ conversation, messages: [] })
    const store = useAiAgentStore()
    await store.loadConversations('connection-1')
    await store.selectConversation('conversation-1', 'connection-1')

    await store.updateConversationTitle('conversation-1', 'Renamed conversation', 'connection-1')

    expect(apiMocks.updateConversation).toHaveBeenCalledWith(
      'conversation-1',
      'connection-1',
      'Renamed conversation',
    )
    expect(store.conversations[0]?.title).toBe('Renamed conversation')
    expect(store.selectedConversation?.title).toBe('Renamed conversation')
  })

  it('applies incremental deltas and resolves an approval while the run stays open', async () => {
    let releaseRun!: () => void
    const runFinished = new Promise<void>((resolve) => (releaseRun = resolve))
    apiMocks.run.mockImplementation(
      async (
        _conversationId: string,
        _connectionId: string,
        _input: string,
        _skillIds: string[],
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

    expect(store.streamingMessageId).toBe('message-1')
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
    expect(store.streamingMessageId).toBeNull()
    expect(store.messages.at(-1)?.id).toBe('message-1')
  })

  it('tracks only the current assistant message while streaming', async () => {
    let finishRun!: () => void
    apiMocks.run.mockImplementation(
      async (
        _conversationId: string,
        _connectionId: string,
        _input: string,
        _skillIds: string[],
        onEvent: (event: AiAgentRunEvent) => void,
      ) => {
        onEvent({ event: 'connected', runId: 'run-1' })
        await new Promise<void>((resolve) => (finishRun = resolve))
      },
    )
    const store = useAiAgentStore()
    store.resetForConnection('connection-1')
    store.selectedConversation = conversation
    store.messages = [
      {
        attachments: [],
        content: '',
        createdAt: 1,
        id: 'historical-empty-assistant',
        role: 'assistant',
      },
    ]

    const run = store.startRun('inspect host', 'connection-1')
    await vi.waitFor(() => expect(store.running).toBe(true))

    expect(store.streamingMessageId).not.toBe('historical-empty-assistant')
    finishRun()
    await run
  })

  it('keeps thinking separate through text resets, thinking resets and multiple model turns', async () => {
    let emit!: (event: AiAgentRunEvent) => void
    let finishRun!: () => void
    apiMocks.run.mockImplementation(async (...args: unknown[]) => {
      emit = args[4] as (event: AiAgentRunEvent) => void
      emit({ event: 'connected', runId: 'run-1' })
      await new Promise<void>((resolve) => (finishRun = resolve))
    })
    const store = useAiAgentStore()
    const run = store.startRun('inspect', 'connection-1')
    await vi.waitFor(() => expect(emit).toBeDefined())
    let sequence = 0
    const send = (event: Extract<AiAgentRunEvent, { messageId: string }>, stepId = 'model-1') =>
      emit({
        ...event,
        runId: 'run-1',
        stepId,
        sequence: ++sequence,
        type: 'model',
        status: 'running',
      })
    send({ event: 'model-start', messageId: 'answer' })
    send({ event: 'thinking-delta', messageId: 'answer', text: 'First ' })
    send({ event: 'thinking-delta', messageId: 'answer', text: 'thought' })
    send({ event: 'message-delta', messageId: 'answer', text: 'Checking' })
    send({ event: 'message-reset', messageId: 'answer' })
    expect(store.runSteps[0]).toMatchObject({
      content: '',
      thinking: 'First thought',
      thinkingRunning: false,
    })
    send({ event: 'message-delta', messageId: 'answer', text: 'I will inspect Docker.' })
    send({ event: 'model-start', messageId: 'answer' }, 'model-2')
    expect(store.messages.at(-1)?.content).toBe('')
    expect(store.runSteps[0]?.content).toBe('I will inspect Docker.')
    send({ event: 'thinking-delta', messageId: 'answer', text: 'Draft' }, 'model-2')
    send({ event: 'thinking-reset', messageId: 'answer' }, 'model-2')
    send({ event: 'thinking-delta', messageId: 'answer', text: 'Final thought' }, 'model-2')
    send({ event: 'thinking-end', messageId: 'answer' }, 'model-2')
    send({ event: 'message-delta', messageId: 'answer', text: 'Answer' }, 'model-2')
    expect(store.messages.at(-1)).toMatchObject({ content: 'Answer', thinking: 'Final thought' })
    expect(store.runSteps.map((step) => step.thinking)).toEqual(['First thought', 'Final thought'])
    finishRun()
    await run
    apiMocks.run.mockResolvedValue(undefined)
    await store.startRun('next question', 'connection-1')
    expect(store.messages.map((message) => message.thinking).filter(Boolean)).toEqual([
      'First thought',
      'Final thought',
    ])
    expect(store.messages.map((message) => message.content)).toEqual([
      'inspect',
      'I will inspect Docker.',
      'Answer',
      'next question',
      '',
    ])
  })

  it('orders run steps and ignores late events from an older run', async () => {
    let emit!: (event: AiAgentRunEvent) => void
    let finishRun!: () => void
    apiMocks.run.mockImplementation(
      async (
        _conversationId: string,
        _connectionId: string,
        _input: string,
        _skillIds: string[],
        onEvent: (event: AiAgentRunEvent) => void,
      ) => {
        emit = onEvent
        onEvent({ event: 'connected', runId: 'run-1', sequence: 1 })
        onEvent({
          event: 'model-start',
          messageId: 'message-1',
          runId: 'run-1',
          sequence: 2,
          startedAt: 1,
          status: 'running',
          stepId: 'model-1',
          type: 'model',
        })
        onEvent({
          event: 'message-delta',
          messageId: 'message-1',
          runId: 'run-1',
          sequence: 4,
          stepId: 'model-1',
          status: 'running',
          text: 'new',
          type: 'model',
        })
        onEvent({
          event: 'message-delta',
          messageId: 'message-1',
          runId: 'run-1',
          sequence: 3,
          stepId: 'model-1',
          status: 'running',
          text: 'late',
          type: 'model',
        })
        await new Promise<void>((resolve) => (finishRun = resolve))
      },
    )
    const store = useAiAgentStore()
    const run = store.startRun('inspect host', 'connection-1')
    await vi.waitFor(() => expect(store.activeRunId).toBe('run-1'))

    emit({
      event: 'message-delta',
      messageId: 'old-message',
      runId: 'old-run',
      sequence: 99,
      text: 'old',
    })
    expect(store.messages.at(-1)?.content).toBe('new')
    expect(store.runSteps).toMatchObject([{ content: 'new', stepId: 'model-1' }])
    finishRun()
    await run
  })

  it.each([false, true])('handles tool approvals with autoRun=%s', async (autoRun) => {
    let finishRun!: () => void
    apiMocks.run.mockImplementation(
      async (
        _conversationId: string,
        _connectionId: string,
        _input: string,
        _skillIds: string[],
        onEvent: (event: AiAgentRunEvent) => void,
      ) => {
        onEvent({ event: 'connected', runId: 'run-1' })
        onEvent({
          event: 'approval-required',
          callId: 'call-1',
          name: 'shell',
          summary: 'Run uptime',
          arguments: { command: 'uptime' },
        })
        await new Promise<void>((resolve) => (finishRun = resolve))
      },
    )
    const store = useAiAgentStore()
    store.resetForConnection('connection-1')
    store.autoRun = autoRun
    const run = store.startRun('inspect host', 'connection-1')
    await vi.waitFor(() => expect(store.activeRunId).toBe('run-1'))
    expect(apiMocks.approve).toHaveBeenCalledTimes(autoRun ? 1 : 0)
    expect(store.toolCalls[0]?.approvalPending).toBe(!autoRun)
    finishRun()
    await run
    store.resetForConnection('connection-2')
    expect(store.autoRun).toBe(autoRun)
  })

  it('hydrates and persists the run permission preference', () => {
    window.localStorage.setItem('host-deck-ui.aiAgent.autoRun', 'true')

    const store = useAiAgentStore()
    expect(store.autoRun).toBe(true)

    expect(store.setAutoRun(false)).toBe(true)
    expect(store.autoRun).toBe(false)
    expect(window.localStorage.getItem('host-deck-ui.aiAgent.autoRun')).toBe('false')

    store.resetForConnection('connection-2')
    expect(store.autoRun).toBe(false)
  })

  it('defaults the run permission preference when storage is unavailable', () => {
    window.localStorage.setItem('host-deck-ui.aiAgent.autoRun', 'invalid')

    const store = useAiAgentStore()
    expect(store.autoRun).toBe(false)
  })

  it('restores manual approval when automatic approval fails', async () => {
    let finishRun!: () => void
    apiMocks.approve.mockRejectedValueOnce(new Error('Approval failed'))
    apiMocks.run.mockImplementation(
      async (
        _conversationId: string,
        _connectionId: string,
        _input: string,
        _skillIds: string[],
        onEvent: (event: AiAgentRunEvent) => void,
      ) => {
        onEvent({ event: 'connected', runId: 'run-1' })
        onEvent({
          event: 'approval-required',
          callId: 'call-1',
          name: 'shell',
          summary: 'Run uptime',
          arguments: {},
        })
        await new Promise<void>((resolve) => (finishRun = resolve))
      },
    )
    const store = useAiAgentStore()
    store.resetForConnection('connection-1')
    store.autoRun = true
    const run = store.startRun('inspect host', 'connection-1')
    await vi.waitFor(() => expect(store.error).toBe('Approval failed'))
    expect(store.toolCalls[0]).toMatchObject({
      approvalPending: true,
      submitting: false,
      status: 'pending',
    })
    finishRun()
    await run
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

  it('restores tool call context when opening a conversation', async () => {
    apiMocks.getConversation.mockResolvedValue({
      conversation,
      messages: [
        { attachments: [], content: 'inspect host', createdAt: 1, id: 'm-user-1', role: 'user' },
        {
          attachments: [],
          content: 'Checking.',
          thinking: 'Inspect the host before answering.',
          createdAt: 2,
          id: 'm-assistant-1',
          role: 'assistant',
          toolCalls: [
            {
              arguments: { command: 'uptime' },
              id: 'call-1',
              name: 'shell_execute',
              summary: 'Execute a remote shell command',
            },
            { arguments: { path: '/etc/hosts' }, id: 'call-2', name: 'file_read' },
          ],
        },
        {
          attachments: [],
          content: 'up 2 days',
          createdAt: 3,
          id: 'm-tool-1',
          role: 'tool',
          toolCallId: 'call-1',
          toolStatus: 'success',
        },
        {
          attachments: [],
          content: 'read failed',
          createdAt: 4,
          id: 'm-tool-2',
          role: 'tool',
          toolCallId: 'call-2',
          toolStatus: 'failed',
        },
        {
          attachments: [],
          content: 'Checking.Done.',
          createdAt: 5,
          id: 'm-final-1',
          role: 'assistant',
          usage: { promptTokens: 120, responseTokens: 30, totalTokens: 150 },
        },
        { attachments: [], content: 'clean up', createdAt: 6, id: 'm-user-2', role: 'user' },
        {
          attachments: [],
          content: 'Working on it.',
          createdAt: 7,
          id: 'm-assistant-2',
          role: 'assistant',
          toolCalls: [{ id: 'call-3', name: 'mcp_3_search', summary: 'Docs: search' }],
        },
      ],
    })
    const store = useAiAgentStore()
    await store.loadConversations('connection-1')
    await store.selectConversation('conversation-1', 'connection-1')

    expect(store.messages.map((message) => message.id)).toEqual([
      'm-user-1',
      'm-assistant-1',
      'm-final-1',
      'm-user-2',
      'm-assistant-2',
    ])
    expect(store.messages[1]).toMatchObject({
      content: 'Checking.',
      thinking: 'Inspect the host before answering.',
    })
    expect(store.toolCalls).toMatchObject([
      {
        arguments: { command: 'uptime' },
        callId: 'call-1',
        result: { content: 'up 2 days' },
        status: 'success',
        summary: 'Execute a remote shell command',
      },
      {
        arguments: { path: '/etc/hosts' },
        callId: 'call-2',
        result: { content: 'read failed' },
        status: 'error',
        summary: 'Read a remote file',
      },
      {
        callId: 'call-3',
        name: 'mcp_3_search',
        result: undefined,
        status: 'cancelled',
        summary: 'Docs: search',
      },
    ])
    expect(store.toolCalls.every((tool) => !tool.approvalPending)).toBe(true)
    expect(store.runSteps.map((step) => step.callId)).toEqual(['call-1', 'call-2', 'call-3'])
    expect(store.runSteps.every((step) => step.restored && step.type === 'tool')).toBe(true)
    expect(store.usage).toEqual({ promptTokens: 120, responseTokens: 30, totalTokens: 150 })
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
        _skillIds: string[],
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
        _skillIds: string[],
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
    store.resetForConnection('connection-1')
    store.skills = [
      {
        description: 'Inspect logs',
        editable: false,
        id: 'logs',
        name: 'Logs',
        source: 'workspace',
      },
    ]
    store.toggleSkill('logs')
    void store.startRun('read file', 'connection-1')
    await vi.waitFor(() => expect(store.activeRunId).toBe('run-1'))

    await store.cancelRun()
    expect(store.running).toBe(false)
    expect(store.selectedSkillIds).toEqual([])
    expect(store.toolCalls[0]).toMatchObject({ approvalPending: false, status: 'cancelled' })

    finishRun()
  })

  it.each([
    ['Tool call limit exceeded.', '已达到工具调用次数上限。'],
    ['Run timed out.', '运行超时，请重试。'],
    ['API key is not configured.', '尚未配置 API Key。'],
  ])('localizes the %s run error event', async (message, localized) => {
    apiMocks.run.mockImplementation(
      async (
        _conversationId: string,
        _connectionId: string,
        _input: string,
        _skillIds: string[],
        onEvent: (event: AiAgentRunEvent) => void,
      ) => {
        onEvent({ event: 'connected', runId: 'run-1' })
        onEvent({ event: 'error', message, status: 'failed' })
        onEvent({ event: 'run-end', status: 'failed' })
      },
    )
    const store = useAiAgentStore()
    store.resetForConnection('connection-1')

    await store.startRun('do something', 'connection-1')

    expect(store.error).toBe(localized)
  })

  it('marks a budget-exhausted run as limit instead of a failure', async () => {
    apiMocks.run.mockImplementation(
      async (
        _conversationId: string,
        _connectionId: string,
        _input: string,
        _skillIds: string[],
        onEvent: (event: AiAgentRunEvent) => void,
      ) => {
        onEvent({ event: 'connected', runId: 'run-1' })
        onEvent({
          event: 'message-delta',
          messageId: 'message-1',
          text: 'The operation stopped after reaching the tool-call limit.',
        })
        onEvent({ event: 'done', conversationId: 'conversation-1', messageId: 'message-1' })
        onEvent({
          event: 'run-end',
          status: 'limit',
          message: 'The operation stopped after reaching the tool-call limit.',
          code: 'TOOL_BUDGET_EXHAUSTED',
        })
      },
    )
    const store = useAiAgentStore()
    store.resetForConnection('connection-1')

    await store.startRun('run a long task', 'connection-1')

    expect(store.runStatus).toBe('limit')
    expect(store.error).toBeNull()
  })

  it('localizes a rejected run start when the conversation is already busy', async () => {
    apiMocks.run.mockRejectedValue(new Error('A run is already active for this conversation.'))
    const store = useAiAgentStore()
    store.resetForConnection('connection-1')

    await expect(store.startRun('again', 'connection-1')).rejects.toThrow()

    expect(store.error).toBe('该会话已有正在运行的任务。')
  })

  it('loads skills, snapshots selections for a run, and clears them when it finishes', async () => {
    apiMocks.run.mockImplementation(
      async (
        _conversationId: string,
        _connectionId: string,
        _input: string,
        _skillIds: string[],
        onEvent: (event: AiAgentRunEvent) => void,
      ) => {
        onEvent({ conversationId: 'conversation-1', event: 'done', messageId: 'message-1' })
      },
    )
    const store = useAiAgentStore()
    await store.loadSkills('connection-1')
    store.toggleSkill('logs')
    store.toggleSkill('services')

    await store.startRun('inspect host', 'connection-1')

    expect(apiMocks.listSkills).toHaveBeenCalledWith('connection-1')
    expect(apiMocks.run).toHaveBeenCalledWith(
      'conversation-1',
      'connection-1',
      'inspect host',
      ['logs', 'services'],
      expect.any(Function),
      expect.any(AbortSignal),
      undefined,
      [],
      'agent',
    )
    expect(store.selectedSkillIds).toEqual([])
  })

  it('manages database skills and reloads the merged list for the active connection', async () => {
    const managedSkill = {
      content: '---\nname: logs\ndescription: Inspect logs\n---\n',
      description: 'Inspect logs',
      editable: true,
      id: 'hostdeck:7',
      name: 'logs',
      source: 'hostdeck',
    }
    apiMocks.createManagedSkill.mockResolvedValue(managedSkill)
    apiMocks.updateManagedSkill.mockResolvedValue(managedSkill)
    apiMocks.getManagedSkill.mockResolvedValue(managedSkill)
    apiMocks.listManagedSkills.mockResolvedValue([managedSkill])
    apiMocks.listSkills.mockResolvedValue([managedSkill])
    const store = useAiAgentStore()
    await store.loadSkills('connection-1')

    await expect(store.createManagedSkill(managedSkill.content)).resolves.toEqual(managedSkill)
    await expect(store.getManagedSkill(7)).resolves.toEqual(managedSkill)
    await expect(store.updateManagedSkill(7, managedSkill.content)).resolves.toEqual(managedSkill)

    expect(apiMocks.listManagedSkills).toHaveBeenCalledTimes(2)
    expect(apiMocks.listSkills).toHaveBeenCalledWith('connection-1')
    expect(store.managedSkills).toEqual([managedSkill])
  })

  it('naturally clears a selected managed skill after deletion reloads the merged list', async () => {
    const managedSkill = {
      description: 'Inspect logs',
      editable: true,
      id: 'hostdeck:7',
      name: 'logs',
      source: 'hostdeck',
    }
    apiMocks.listSkills.mockResolvedValueOnce([managedSkill]).mockResolvedValueOnce([])
    apiMocks.listManagedSkills.mockResolvedValue([])
    const store = useAiAgentStore()
    await store.loadSkills('connection-1')
    store.toggleSkill(managedSkill.id)

    await store.deleteManagedSkill(7)

    expect(apiMocks.deleteManagedSkill).toHaveBeenCalledWith(7)
    expect(store.selectedSkillIds).toEqual([])
  })

  it('keeps a successful deletion when remote skill refresh fails', async () => {
    const managedSkill = {
      description: 'Inspect logs',
      editable: true,
      id: 'hostdeck:7',
      name: 'logs',
      source: 'hostdeck',
    }
    apiMocks.listSkills
      .mockResolvedValueOnce([managedSkill])
      .mockRejectedValueOnce(new Error('SFTP down'))
    apiMocks.listManagedSkills.mockResolvedValue([])
    const store = useAiAgentStore()
    await store.loadSkills('connection-1')
    store.toggleSkill(managedSkill.id)

    await expect(store.deleteManagedSkill(7)).resolves.toBeUndefined()
    expect(store.selectedSkillIds).toEqual([])
    expect(store.skills).toEqual([])
    expect(store.managedSkills).toEqual([])
  })

  it('ignores an older managed skill listing after a later refresh', async () => {
    let resolveOld!: (value: never[]) => void
    apiMocks.listManagedSkills
      .mockReturnValueOnce(
        new Promise((resolve) => {
          resolveOld = resolve
        }),
      )
      .mockResolvedValueOnce([
        { id: 'hostdeck:7', name: 'logs', description: 'Logs', source: 'hostdeck', editable: true },
      ])
    const store = useAiAgentStore()
    const older = store.loadManagedSkills()
    await store.loadManagedSkills()
    resolveOld([])
    await older

    expect(store.managedSkills).toHaveLength(1)
    expect(store.loadingManagedSkills).toBe(false)
  })

  it('sends and renders an image-only user message', async () => {
    apiMocks.run.mockImplementation(
      async (
        _conversationId: string,
        _connectionId: string,
        _input: string,
        _skillIds: string[],
        onEvent: (event: AiAgentRunEvent) => void,
      ) => {
        onEvent({ conversationId: 'conversation-1', event: 'done', messageId: 'message-1' })
      },
    )
    const attachment = { data: 'aGVsbG8=', mimeType: 'image/png', name: 'screen.png' }
    const store = useAiAgentStore()

    await store.startRun('', 'connection-1', [attachment])

    expect(store.messages[0]).toMatchObject({
      attachments: [attachment],
      content: '',
      role: 'user',
    })
    expect(apiMocks.run).toHaveBeenCalledWith(
      'conversation-1',
      'connection-1',
      '',
      [],
      expect.any(Function),
      expect.any(AbortSignal),
      undefined,
      [attachment],
      'agent',
    )
  })

  it('clears selected skills and sends chat mode without agent capabilities', async () => {
    apiMocks.run.mockImplementation(
      async (
        _conversationId: string,
        _connectionId: string,
        _input: string,
        _skillIds: string[],
        onEvent: (event: AiAgentRunEvent) => void,
      ) => {
        onEvent({ conversationId: 'conversation-1', event: 'done', messageId: 'message-1' })
      },
    )
    const store = useAiAgentStore()
    await store.loadSkills('connection-1')
    store.toggleSkill('logs')

    store.setRunMode('chat')
    await store.startRun('explain load average', 'connection-1')

    expect(store.selectedSkillIds).toEqual([])
    expect(apiMocks.run).toHaveBeenCalledWith(
      'conversation-1',
      'connection-1',
      'explain load average',
      [],
      expect.any(Function),
      expect.any(AbortSignal),
      undefined,
      [],
      'chat',
    )
  })

  it('clears skills when the connection changes and after a failed run', async () => {
    const store = useAiAgentStore()
    await store.loadSkills('connection-1')
    store.toggleSkill('logs')
    store.resetForConnection('connection-2')

    expect(store.skills).toEqual([])
    expect(store.selectedSkillIds).toEqual([])

    await store.loadSkills('connection-2')
    store.toggleSkill('logs')
    apiMocks.run.mockRejectedValue(new Error('run failed'))
    await expect(store.startRun('inspect host', 'connection-2')).rejects.toThrow('run failed')
    expect(store.selectedSkillIds).toEqual([])
  })

  it('limits each run to eight selected skills', () => {
    const store = useAiAgentStore()
    store.skills = Array.from({ length: MAX_SELECTED_SKILLS + 1 }, (_, index) => ({
      description: `Skill ${index}`,
      editable: false,
      id: `skill-${index}`,
      name: `skill-${index}`,
      source: 'opencode',
    }))

    store.setSelectedSkillIds(store.skills.map((skill) => skill.id))

    expect(store.selectedSkillIds).toHaveLength(MAX_SELECTED_SKILLS)
    expect(store.selectedSkillIds).not.toContain(`skill-${MAX_SELECTED_SKILLS}`)
  })
})
