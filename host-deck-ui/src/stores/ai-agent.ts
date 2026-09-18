import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import {
  aiAgentApi,
  type AiAgentConversation,
  type AiAgentImageAttachment,
  type AiAgentMessage,
  type AiAgentMcpServer,
  type AiAgentMcpServerInput,
  type AiAgentRunEvent,
  type AiAgentSettings,
  type AiAgentSettingsUpdate,
  type AiAgentSkill,
  type AiAgentUsage,
} from '@/api/ai-agent'

const MAX_CONVERSATIONS = 200
const MAX_MESSAGES = 300
const MAX_TOOL_CALLS = 100
export const MAX_SELECTED_SKILLS = 8

export type AiAgentToolStatus = 'pending' | 'running' | 'success' | 'error' | 'rejected'

export interface AiAgentToolCall {
  callId: string
  name: string
  summary: string
  status: AiAgentToolStatus
  arguments?: unknown
  approvalPending: boolean
  submitting: boolean
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : '请求失败，请稍后重试。'
}

function temporaryMessage(
  role: 'assistant' | 'user',
  content: string,
  attachments: AiAgentImageAttachment[] = [],
): AiAgentMessage {
  return {
    attachments,
    content,
    createdAt: Date.now(),
    id: `local-${role}-${Date.now()}-${Math.random().toString(36).slice(2)}`,
    role,
  }
}

export const useAiAgentStore = defineStore('ai-agent', () => {
  const settings = ref<AiAgentSettings | null>(null)
  const skills = ref<AiAgentSkill[]>([])
  const mcpServers = ref<AiAgentMcpServer[]>([])
  const selectedSkillIds = ref<string[]>([])
  const conversations = ref<AiAgentConversation[]>([])
  const currentConnectionId = ref<string | null>(null)
  const selectedConversation = ref<AiAgentConversation | null>(null)
  const messages = ref<AiAgentMessage[]>([])
  const toolCalls = ref<AiAgentToolCall[]>([])
  const usage = ref<AiAgentUsage | null>(null)
  const durationMs = ref<number | null>(null)
  const loadingSettings = ref(false)
  const loadingSkills = ref(false)
  const loadingMcpServers = ref(false)
  const loadingConversations = ref(false)
  const loadingConversation = ref(false)
  const running = ref(false)
  const autoRun = ref(false)
  const activeRunId = ref<string | null>(null)
  const error = ref<string | null>(null)
  const skillsError = ref<string | null>(null)

  let listRequest = 0
  let detailRequest = 0
  let skillsRequest = 0
  let runRequest = 0
  let runController: AbortController | null = null
  let runStartedAt: number | null = null

  function finishRunTiming() {
    if (runStartedAt === null) return
    durationMs.value = performance.now() - runStartedAt
    runStartedAt = null
  }

  const hasPendingApproval = computed(() => toolCalls.value.some((tool) => tool.approvalPending))

  async function loadSettings() {
    loadingSettings.value = true
    try {
      settings.value = await aiAgentApi.getSettings()
      return settings.value
    } finally {
      loadingSettings.value = false
    }
  }

  async function saveSettings(payload: AiAgentSettingsUpdate) {
    settings.value = await aiAgentApi.saveSettings(payload)
    return settings.value
  }

  async function testSettings(payload?: AiAgentSettingsUpdate) {
    return aiAgentApi.testSettings(payload)
  }

  async function loadModels() {
    return aiAgentApi.listModels()
  }

  async function loadSkills(connectionId: string) {
    resetForConnection(connectionId)
    const request = ++skillsRequest
    loadingSkills.value = true
    skillsError.value = null
    try {
      const result = await aiAgentApi.listSkills(connectionId)
      if (request !== skillsRequest || currentConnectionId.value !== connectionId) return
      skills.value = result
      const availableIds = new Set(result.map((skill) => skill.id))
      selectedSkillIds.value = selectedSkillIds.value.filter((id) => availableIds.has(id))
    } catch (requestError) {
      if (request === skillsRequest) skillsError.value = errorMessage(requestError)
      throw requestError
    } finally {
      if (request === skillsRequest) loadingSkills.value = false
    }
  }

  async function loadMcpServers() {
    loadingMcpServers.value = true
    try {
      mcpServers.value = await aiAgentApi.listMcpServers()
      return mcpServers.value
    } finally {
      loadingMcpServers.value = false
    }
  }

  async function createMcpServer(payload: AiAgentMcpServerInput) {
    const server = await aiAgentApi.createMcpServer(payload)
    mcpServers.value = [...mcpServers.value, server].sort((a, b) => a.name.localeCompare(b.name))
    return server
  }

  async function updateMcpServer(id: number, payload: AiAgentMcpServerInput) {
    const server = await aiAgentApi.updateMcpServer(id, payload)
    mcpServers.value = mcpServers.value
      .map((item) => (item.id === id ? server : item))
      .sort((a, b) => a.name.localeCompare(b.name))
    return server
  }

  async function deleteMcpServer(id: number) {
    await aiAgentApi.deleteMcpServer(id)
    mcpServers.value = mcpServers.value.filter((item) => item.id !== id)
  }

  async function testMcpServer(id: number) {
    return aiAgentApi.testMcpServer(id)
  }

  function setSelectedSkillIds(ids: string[]) {
    const availableIds = new Set(skills.value.map((skill) => skill.id))
    selectedSkillIds.value = [...new Set(ids.filter((id) => availableIds.has(id)))].slice(
      0,
      MAX_SELECTED_SKILLS,
    )
  }

  function toggleSkill(id: string) {
    if (running.value || !skills.value.some((skill) => skill.id === id)) return
    setSelectedSkillIds(
      selectedSkillIds.value.includes(id)
        ? selectedSkillIds.value.filter((selectedId) => selectedId !== id)
        : [...selectedSkillIds.value, id],
    )
  }

  function resetForConnection(connectionId: string | null) {
    if (currentConnectionId.value === connectionId) return false
    abortRun()
    currentConnectionId.value = connectionId
    autoRun.value = false
    conversations.value = []
    skills.value = []
    selectedSkillIds.value = []
    selectedConversation.value = null
    messages.value = []
    toolCalls.value = []
    usage.value = null
    durationMs.value = null
    error.value = null
    skillsError.value = null
    loadingSkills.value = false
    listRequest += 1
    detailRequest += 1
    skillsRequest += 1
    return true
  }

  async function loadConversations(connectionId: string) {
    resetForConnection(connectionId)
    const request = ++listRequest
    loadingConversations.value = true
    error.value = null
    try {
      const result = await aiAgentApi.listConversations(connectionId)
      if (request !== listRequest || currentConnectionId.value !== connectionId) return
      conversations.value = result.slice(0, MAX_CONVERSATIONS)
      if (selectedConversation.value) {
        selectedConversation.value =
          conversations.value.find((item) => item.id === selectedConversation.value?.id) ??
          selectedConversation.value
      }
    } catch (requestError) {
      if (request === listRequest) error.value = errorMessage(requestError)
      throw requestError
    } finally {
      if (request === listRequest) loadingConversations.value = false
    }
  }

  async function createConversation(connectionId: string, allowWhileRunning = false) {
    if (running.value && !allowWhileRunning) return null
    resetForConnection(connectionId)
    const conversation = await aiAgentApi.createConversation(connectionId)
    if (currentConnectionId.value !== connectionId) return null
    conversations.value = [
      conversation,
      ...conversations.value.filter((item) => item.id !== conversation.id),
    ].slice(0, MAX_CONVERSATIONS)
    selectedConversation.value = conversation
    messages.value = []
    toolCalls.value = []
    usage.value = null
    durationMs.value = null
    error.value = null
    detailRequest += 1
    return conversation
  }

  async function selectConversation(id: string, connectionId: string) {
    resetForConnection(connectionId)
    if (running.value) return
    const request = ++detailRequest
    loadingConversation.value = true
    error.value = null
    try {
      const result = await aiAgentApi.getConversation(id, connectionId)
      if (request !== detailRequest || currentConnectionId.value !== connectionId) return
      selectedConversation.value = result.conversation
      messages.value = result.messages.slice(-MAX_MESSAGES)
      toolCalls.value = []
      usage.value = null
      durationMs.value = null
    } catch (requestError) {
      if (request === detailRequest) error.value = errorMessage(requestError)
      throw requestError
    } finally {
      if (request === detailRequest) loadingConversation.value = false
    }
  }

  async function deleteConversation(id: string, connectionId: string) {
    if (running.value && selectedConversation.value?.id === id) await cancelRun()
    await aiAgentApi.deleteConversation(id, connectionId)
    if (currentConnectionId.value !== connectionId) return
    conversations.value = conversations.value.filter((item) => item.id !== id)
    if (selectedConversation.value?.id === id) {
      selectedConversation.value = null
      messages.value = []
      toolCalls.value = []
      usage.value = null
      durationMs.value = null
      detailRequest += 1
    }
  }

  async function updateConversationTitle(id: string, title: string, connectionId: string) {
    const conversation = await aiAgentApi.updateConversation(id, connectionId, title)
    if (currentConnectionId.value !== connectionId) return null
    conversations.value = conversations.value.map((item) =>
      item.id === conversation.id ? conversation : item,
    )
    if (selectedConversation.value?.id === conversation.id) {
      selectedConversation.value = conversation
    }
    return conversation
  }

  function upsertTool(event: Extract<AiAgentRunEvent, { callId: string }>) {
    const existing = toolCalls.value.find((tool) => tool.callId === event.callId)
    if (existing) {
      existing.name = event.name
      existing.summary = event.summary
      if (event.event === 'approval-required') {
        existing.arguments = event.arguments
        existing.approvalPending = true
        existing.status = 'pending'
      } else if (event.event === 'tool-result') {
        existing.approvalPending = false
        existing.status = event.success
          ? 'success'
          : existing.status === 'rejected'
            ? 'rejected'
            : 'error'
      } else {
        existing.status = 'running'
      }
      return
    }
    const nextTool: AiAgentToolCall = {
      approvalPending: event.event === 'approval-required',
      arguments: event.event === 'approval-required' ? event.arguments : undefined,
      callId: event.callId,
      name: event.name,
      status:
        event.event === 'approval-required'
          ? 'pending'
          : event.event === 'tool-result'
            ? event.success
              ? 'success'
              : 'error'
            : 'running',
      submitting: false,
      summary: event.summary,
    }
    toolCalls.value = [...toolCalls.value, nextTool].slice(-MAX_TOOL_CALLS)
  }

  function applyRunEvent(event: AiAgentRunEvent, assistant: AiAgentMessage) {
    if (event.event === 'connected') {
      activeRunId.value = event.runId
    } else if (event.event === 'message-delta') {
      assistant.id = event.messageId
      assistant.content += event.text
    } else if (
      event.event === 'tool-start' ||
      event.event === 'approval-required' ||
      event.event === 'tool-result'
    ) {
      upsertTool(event)
      if (event.event === 'approval-required' && autoRun.value) {
        void resolveApproval(event.callId, true).catch(() => undefined)
      }
    } else if (event.event === 'usage') {
      usage.value = event.usage
    } else if (event.event === 'done') {
      assistant.id = event.messageId
      finishRunTiming()
    }
  }

  async function startRun(
    input: string,
    connectionId: string,
    attachments: AiAgentImageAttachment[] = [],
  ) {
    const trimmedInput = input.trim()
    if ((!trimmedInput && attachments.length === 0) || running.value) return false
    resetForConnection(connectionId)
    const runSkillIds = [...selectedSkillIds.value]
    const model = settings.value?.model
    const request = ++runRequest
    const controller = new AbortController()
    runController = controller
    running.value = true
    let completed = false

    try {
      if (!selectedConversation.value) {
        const created = await createConversation(connectionId, true)
        if (!created) return false
      }
      const conversationId = selectedConversation.value!.id
      const userMessage = temporaryMessage('user', trimmedInput, attachments)
      const assistantMessage = temporaryMessage('assistant', '')
      messages.value = [...messages.value, userMessage, assistantMessage].slice(-MAX_MESSAGES)
      const streamedAssistant = messages.value.at(-1)!
      toolCalls.value = []
      usage.value = null
      durationMs.value = null
      runStartedAt = performance.now()
      error.value = null
      activeRunId.value = null
      const onEvent = (event: AiAgentRunEvent) => {
        if (request === runRequest) applyRunEvent(event, streamedAssistant)
      }
      if (model) {
        await aiAgentApi.run(
          conversationId,
          connectionId,
          trimmedInput,
          runSkillIds,
          onEvent,
          controller.signal,
          model,
          attachments,
        )
      } else if (attachments.length) {
        await aiAgentApi.run(
          conversationId,
          connectionId,
          trimmedInput,
          runSkillIds,
          onEvent,
          controller.signal,
          undefined,
          attachments,
        )
      } else {
        await aiAgentApi.run(
          conversationId,
          connectionId,
          trimmedInput,
          runSkillIds,
          onEvent,
          controller.signal,
        )
      }
      completed = true
      if (request === runRequest) {
        void loadConversations(connectionId).catch(() => undefined)
      }
      return true
    } catch (runError) {
      if (request === runRequest && !controller.signal.aborted) {
        error.value = errorMessage(runError)
      }
      if (!controller.signal.aborted) throw runError
      return false
    } finally {
      if (request === runRequest) {
        finishRunTiming()
        if (!completed) finishPendingTools('error')
        running.value = false
        activeRunId.value = null
        runController = null
        selectedSkillIds.value = []
      }
    }
  }

  function abortRun() {
    finishRunTiming()
    runRequest += 1
    runController?.abort()
    runController = null
    running.value = false
    activeRunId.value = null
    selectedSkillIds.value = []
    finishPendingTools('error')
  }

  async function cancelRun() {
    const runId = activeRunId.value
    const controller = runController
    if (!controller) return
    const cancellation = runId ? aiAgentApi.cancel(runId) : Promise.resolve()
    finishRunTiming()
    controller.abort()
    finishPendingTools('error')
    try {
      await cancellation
    } finally {
      if (runController === controller) abortRun()
    }
  }

  async function resolveApproval(callId: string, approved: boolean) {
    const runId = activeRunId.value
    const tool = toolCalls.value.find((item) => item.callId === callId)
    if (!runId || !tool || !tool.approvalPending || tool.submitting) return
    tool.submitting = true
    tool.approvalPending = false
    tool.status = approved ? 'running' : 'rejected'
    try {
      if (approved) {
        await aiAgentApi.approve(runId, callId)
      } else {
        await aiAgentApi.reject(runId, callId)
      }
    } catch (approvalError) {
      tool.approvalPending = true
      tool.status = 'pending'
      error.value = errorMessage(approvalError)
      throw approvalError
    } finally {
      tool.submitting = false
    }
  }

  function finishPendingTools(status: 'error' | 'rejected') {
    for (const tool of toolCalls.value) {
      if (tool.approvalPending || tool.status === 'running') {
        tool.approvalPending = false
        tool.submitting = false
        tool.status = status
      }
    }
  }

  return {
    activeRunId,
    autoRun,
    cancelRun,
    conversations,
    createConversation,
    currentConnectionId,
    deleteConversation,
    durationMs,
    error,
    hasPendingApproval,
    loadConversations,
    loadMcpServers,
    loadModels,
    loadSkills,
    loadSettings,
    loadingConversation,
    loadingConversations,
    loadingMcpServers,
    loadingSettings,
    loadingSkills,
    messages,
    mcpServers,
    resetForConnection,
    resolveApproval,
    running,
    saveSettings,
    selectedSkillIds,
    selectedConversation,
    selectConversation,
    settings,
    setSelectedSkillIds,
    skills,
    skillsError,
    startRun,
    testSettings,
    testMcpServer,
    toggleSkill,
    toolCalls,
    createMcpServer,
    deleteMcpServer,
    updateMcpServer,
    updateConversationTitle,
    usage,
  }
})
