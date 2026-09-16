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
    )
    expect(store.selectedSkillIds).toEqual([])
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
