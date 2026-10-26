import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { AiAgentRunEvent } from '@/api/ai-agent'
import { useAiAgentStore } from '@/stores/ai-agent'

const apiMocks = vi.hoisted(() => ({
  approve: vi.fn(),
  cancel: vi.fn(),
  createConversation: vi.fn(),
  getSettings: vi.fn(),
  listConversations: vi.fn(),
  reject: vi.fn(),
  run: vi.fn(),
}))

const notificationMocks = vi.hoisted(() => ({
  browserNotificationPermission: vi.fn<() => 'granted' | 'denied' | 'default' | 'unsupported'>(
    () => 'granted',
  ),
  requestBrowserNotificationPermission: vi.fn(async () => 'granted' as const),
  showBrowserNotification: vi.fn(),
}))

vi.mock('@/api/ai-agent', () => ({ aiAgentApi: apiMocks }))
vi.mock('@/lib/browser-notification', () => notificationMocks)

const conversation = {
  createdAt: 1,
  id: 'conversation-1',
  title: 'Maintain host',
  updatedAt: 1,
}

const successEvents: AiAgentRunEvent[] = [
  { event: 'connected', runId: 'run-1' },
  { event: 'message-delta', messageId: 'message-1', text: 'All services are healthy.' },
  { event: 'done', conversationId: 'conversation-1', messageId: 'message-1' },
  { event: 'run-end', status: 'success' },
]

const questionEvents: AiAgentRunEvent[] = [
  { event: 'connected', runId: 'run-1' },
  {
    event: 'question-required',
    callId: 'ask-1',
    name: 'ask_user_question',
    questions: [
      {
        id: 'q1',
        multiSelect: false,
        options: [{ label: 'Yes' }, { label: 'No' }],
        question: 'Proceed with restart?',
      },
    ],
    summary: 'Ask the user a question',
  },
  { event: 'run-end', status: 'success' },
]

function emitEvents(events: AiAgentRunEvent[]) {
  apiMocks.run.mockImplementation(
    async (
      _conversationId: string,
      _connectionId: string,
      _input: string,
      _skillIds: string[],
      onEvent: (event: AiAgentRunEvent) => void,
    ) => {
      for (const event of events) onEvent(event)
    },
  )
}

function setPageState({ focused = true, visible = true } = {}) {
  Object.defineProperty(document, 'visibilityState', {
    configurable: true,
    get: () => (visible ? 'visible' : 'hidden'),
  })
  vi.spyOn(document, 'hasFocus').mockReturnValue(focused)
}

async function startRun(
  events: AiAgentRunEvent[],
  context?: { focusWindow?: () => void; isWindowActive: () => boolean },
) {
  const store = useAiAgentStore()
  if (context) store.setNotificationContext(context)
  emitEvents(events)
  await store.startRun('inspect host', 'connection-1')
  return store
}

function shownNotifications() {
  return notificationMocks.showBrowserNotification.mock.calls.map(
    ([options]) => options as { body?: string; onClick?: () => void; tag?: string; title: string },
  )
}

describe('AI Agent notifications', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    window.localStorage.clear()
    vi.clearAllMocks()
    setPageState()
    notificationMocks.browserNotificationPermission.mockReturnValue('granted')
    notificationMocks.requestBrowserNotificationPermission.mockResolvedValue('granted')
    apiMocks.approve.mockResolvedValue(undefined)
    apiMocks.cancel.mockResolvedValue(undefined)
    apiMocks.createConversation.mockResolvedValue(conversation)
    apiMocks.listConversations.mockResolvedValue([conversation])
    apiMocks.reject.mockResolvedValue(undefined)
  })

  afterEach(() => {
    vi.restoreAllMocks()
    Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'visible' })
  })

  it('notifies about a completed run when the agent window is in the background', async () => {
    const focusWindow = vi.fn()
    await startRun(successEvents, { focusWindow, isWindowActive: () => false })

    const notifications = shownNotifications()
    expect(notifications).toHaveLength(1)
    expect(notifications[0]!.title).toBe('AI Agent 任务已完成')
    expect(notifications[0]!.body).toContain('Maintain host')
    expect(notifications[0]!.body).toContain('All services are healthy.')
    expect(notifications[0]!.tag).toBe('ai-agent-run-conversation-1')

    notifications[0]!.onClick?.()
    expect(focusWindow).toHaveBeenCalledTimes(1)
  })

  it('stays quiet while the agent window is active and focused', async () => {
    await startRun(successEvents, { isWindowActive: () => true })
    expect(notificationMocks.showBrowserNotification).not.toHaveBeenCalled()
  })

  it('notifies when the page itself is hidden or unfocused', async () => {
    setPageState({ visible: false })
    await startRun(successEvents)
    expect(notificationMocks.showBrowserNotification).toHaveBeenCalledTimes(1)

    notificationMocks.showBrowserNotification.mockClear()
    setPageState({ focused: false })
    await startRun(successEvents)
    expect(notificationMocks.showBrowserNotification).toHaveBeenCalledTimes(1)
  })

  it('notifies about a failed run with the localized error', async () => {
    await startRun(
      [
        { event: 'connected', runId: 'run-1' },
        { event: 'error', message: 'The AI agent run failed.' },
        { event: 'run-end', status: 'failed' },
      ],
      { isWindowActive: () => false },
    )

    const notifications = shownNotifications()
    expect(notifications).toHaveLength(1)
    expect(notifications[0]!.title).toBe('AI Agent 任务失败')
    expect(notifications[0]!.body).toBe('Agent 运行失败，请稍后重试。')
  })

  it('marks a budget-limited run as completed', async () => {
    await startRun(
      [
        { event: 'connected', runId: 'run-1' },
        { event: 'message-delta', messageId: 'message-1', text: 'Stopped at the limit.' },
        { event: 'run-end', status: 'limit' },
      ],
      { isWindowActive: () => false },
    )

    expect(shownNotifications()[0]!.title).toBe('AI Agent 任务已完成（工具预算用尽）')
  })

  it('does not notify about a cancelled or expired run', async () => {
    await startRun(
      [
        { event: 'connected', runId: 'run-1' },
        { event: 'run-end', status: 'cancelled' },
      ],
      { isWindowActive: () => false },
    )
    expect(notificationMocks.showBrowserNotification).not.toHaveBeenCalled()

    await startRun(
      [
        { event: 'connected', runId: 'run-1' },
        { event: 'run-end', status: 'expired' },
      ],
      { isWindowActive: () => false },
    )
    expect(notificationMocks.showBrowserNotification).not.toHaveBeenCalled()
  })

  it('notifies when the agent asks a question', async () => {
    await startRun(questionEvents, { isWindowActive: () => false })

    const question = shownNotifications().find(
      (notification) => notification.title === 'AI Agent 需要你的回答',
    )
    expect(question).toBeDefined()
    expect(question!.body).toContain('Maintain host')
    expect(question!.body).toContain('Proceed with restart?')
    expect(question!.tag).toBe('ai-agent-question-conversation-1')
  })

  it('respects disabled notification preferences', async () => {
    const store = useAiAgentStore()
    store.setNotificationPreference('runComplete', false)
    await startRun(successEvents, { isWindowActive: () => false })
    expect(notificationMocks.showBrowserNotification).not.toHaveBeenCalled()

    store.setNotificationPreference('question', false)
    await startRun(questionEvents, { isWindowActive: () => false })
    expect(
      shownNotifications().some((notification) => notification.title === 'AI Agent 需要你的回答'),
    ).toBe(false)
  })

  it('skips notifications when the browser permission is not granted', async () => {
    notificationMocks.browserNotificationPermission.mockReturnValue('default')
    await startRun(successEvents, { isWindowActive: () => false })
    expect(notificationMocks.showBrowserNotification).not.toHaveBeenCalled()
  })

  it('asks for notification permission only once on the first run', async () => {
    notificationMocks.browserNotificationPermission.mockReturnValue('default')
    await startRun(successEvents, { isWindowActive: () => false })
    await startRun(successEvents, { isWindowActive: () => false })
    expect(notificationMocks.requestBrowserNotificationPermission).toHaveBeenCalledTimes(1)
  })

  it('persists notification preferences across stores', () => {
    const store = useAiAgentStore()
    store.setNotificationPreference('question', false)

    setActivePinia(createPinia())
    const restored = useAiAgentStore()
    expect(restored.notificationPreferences).toEqual({ question: false, runComplete: true })
  })
})
