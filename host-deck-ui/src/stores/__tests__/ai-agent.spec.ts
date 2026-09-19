import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { AiAgentRunEvent } from '@/api/ai-agent'
import { MAX_SELECTED_SKILLS, useAiAgentStore } from '@/stores/ai-agent'

const apiMocks = vi.hoisted(() => ({
  approve: vi.fn(),
  cancel: vi.fn(),
  createConversation: vi.fn(),
  deleteConversation: vi.fn(),
  getConversation: vi.fn(),
  getSettings: vi.fn(),
  listConversations: vi.fn(),
  listSkills: vi.fn(),
  reject: vi.fn(),
  run: vi.fn(),
  saveSettings: vi.fn(),
  testSettings: vi.fn(),
  updateConversation: vi.fn(),
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
    window.localStorage.clear()
    vi.clearAllMocks()
    apiMocks.createConversation.mockResolvedValue(conversation)
    apiMocks.listConversations.mockResolvedValue([conversation])
    apiMocks.listSkills.mockResolvedValue([
      { description: 'Inspect logs', id: 'logs', name: 'Logs', source: 'workspace' },
      { description: 'Review services', id: 'services', name: 'Services', source: 'builtin' },
    ])
    apiMocks.approve.mockResolvedValue(undefined)
    apiMocks.cancel.mockResolvedValue(undefined)
    apiMocks.reject.mockResolvedValue(undefined)
    apiMocks.updateConversation.mockResolvedValue({
      ...conversation,
      title: 'Renamed conversation',
    })
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
      'm-final-1',
      'm-user-2',
      'm-assistant-2',
    ])
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
        status: 'error',
        summary: 'Docs: search',
      },
    ])
    expect(store.toolCalls.every((tool) => !tool.approvalPending)).toBe(true)
    expect(store.runSteps.map((step) => step.callId)).toEqual(['call-1', 'call-2', 'call-3'])
    expect(store.runSteps.every((step) => step.restored && step.type === 'tool')).toBe(true)
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
    store.skills = [{ description: 'Inspect logs', id: 'logs', name: 'Logs', source: 'workspace' }]
    store.toggleSkill('logs')
    void store.startRun('read file', 'connection-1')
    await vi.waitFor(() => expect(store.activeRunId).toBe('run-1'))

    await store.cancelRun()
    expect(store.running).toBe(false)
    expect(store.selectedSkillIds).toEqual([])
    expect(store.toolCalls[0]).toMatchObject({ approvalPending: false, status: 'error' })

    finishRun()
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
      id: `skill-${index}`,
      name: `skill-${index}`,
      source: 'opencode',
    }))

    store.setSelectedSkillIds(store.skills.map((skill) => skill.id))

    expect(store.selectedSkillIds).toHaveLength(MAX_SELECTED_SKILLS)
    expect(store.selectedSkillIds).not.toContain(`skill-${MAX_SELECTED_SKILLS}`)
  })
})
