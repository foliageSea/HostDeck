import { computed, ref, watch } from 'vue'
import { defineStore } from 'pinia'
import {
  aiAgentApi,
  type AiAgentConversation,
  type AiAgentImageAttachment,
  type AiAgentMessage,
  type AiAgentMcpServer,
  type AiAgentMcpServerInput,
  type AiAgentRunEvent,
  type AiAgentRunStatus,
  type AiAgentRunStep,
  type AiAgentToolResult,
  type AiAgentRunMode,
  type AiAgentSettings,
  type AiAgentSettingsUpdate,
  type AiAgentSkill,
  type AiAgentUsage,
} from '@/api/ai-agent'

const MAX_CONVERSATIONS = 200
const MAX_MESSAGES = 300
const MAX_TOOL_CALLS = 100
export const MAX_SELECTED_SKILLS = 8

const AUTO_RUN_STORAGE_KEY = 'host-deck-ui.aiAgent.autoRun'

export type AiAgentToolStatus =
  | 'pending'
  | 'running'
  | 'success'
  | 'error'
  | 'rejected'
  | 'expired'
  | 'cancelled'

export interface AiAgentToolCall {
  callId: string
  name: string
  summary: string
  status: AiAgentToolStatus
  arguments?: unknown
  result?: AiAgentToolResult
  approvalPending: boolean
  submitting: boolean
}

const TOOL_SUMMARIES: Record<string, string> = {
  apply_patch: 'Apply a remote patch',
  file_read: 'Read a remote file',
  file_write: 'Write a remote file',
  process_list: 'Read process list',
  shell_execute: 'Execute a remote shell command',
  system_status: 'Read system status',
}

function restoredToolSummary(name: string) {
  return TOOL_SUMMARIES[name] ?? name
}

function restoredToolStatus(
  toolStatus: AiAgentMessage['toolStatus'],
  hasResult: boolean,
): AiAgentToolStatus {
  if (toolStatus === 'rejected') return 'rejected'
  if (toolStatus === 'expired') return 'expired'
  if (toolStatus === 'cancelled') return 'cancelled'
  if (toolStatus === 'failed') return 'error'
  if (toolStatus === 'success') return 'success'
  return hasResult ? 'success' : 'cancelled'
}

function restoredStepStatus(status: AiAgentToolStatus) {
  if (status === 'rejected') return 'rejected' as const
  if (status === 'expired') return 'expired' as const
  if (status === 'cancelled') return 'cancelled' as const
  if (status === 'success') return 'success' as const
  return 'failed' as const
}

function restoreConversation(loaded: AiAgentMessage[]) {
  const toolResults = new Map<
    string,
    { content: string; status?: AiAgentMessage['toolStatus']; result?: AiAgentToolResult }
  >()
  for (const message of loaded) {
    if (message.role === 'tool' && message.toolCallId) {
      toolResults.set(message.toolCallId, {
        content: message.content,
        status: message.toolStatus,
        result: message.toolResult,
      })
    }
  }

  const messages: AiAgentMessage[] = []
  const steps: AiAgentRunStep[] = []
  const tools: AiAgentToolCall[] = []
  const segments: AiAgentMessage[][] = []
  for (const message of loaded) {
    if (message.role === 'user' || segments.length === 0) segments.push([])
    segments.at(-1)!.push(message)
  }

  let sequence = 0
  for (const segment of segments) {
    const last = segment.at(-1)
    const completed =
      last !== undefined && last.role === 'assistant' && !(last.toolCalls?.length ?? 0)
    for (const message of segment) {
      if (message.role === 'user') {
        messages.push(message)
        continue
      }
      if (message.role === 'error') {
        messages.push({ ...message, content: localizeRunMessage(message.content) })
        continue
      }
      if (message.role !== 'assistant') continue
      const calls = message.toolCalls ?? []
      if (calls.length === 0) {
        messages.push(message)
        continue
      }
      if (!completed && message.content) messages.push(message)
      for (const call of calls) {
        const result = toolResults.get(call.id)
        const status = restoredToolStatus(result?.status, result !== undefined)
        steps.push({
          arguments: call.arguments,
          callId: call.id,
          name: call.name,
          restored: true,
          runId: '',
          sequence: sequence++,
          startedAt: message.createdAt,
          status: restoredStepStatus(status),
          stepId: `restored-${call.id}`,
          type: 'tool',
        })
        tools.push({
          arguments: call.arguments,
          approvalPending: false,
          callId: call.id,
          name: call.name,
          result: result ? { ...result.result, content: result.content } : undefined,
          status,
          submitting: false,
          summary: call.summary ?? restoredToolSummary(call.name),
        })
      }
    }
  }

  const restoredUsage = [...loaded]
    .reverse()
    .find((message) => message.role === 'assistant' && message.usage)?.usage ?? null

  return { messages, steps, tools, usage: restoredUsage }
}

function errorMessage(error: unknown) {
  return localizeRunMessage(error instanceof Error ? error.message : '请求失败，请稍后重试。')
}

function localizeRunMessage(message: string) {
  return (
    {
      'API key is not configured.': '尚未配置 API Key。',
      'The AI agent run could not be completed.': 'Agent 运行失败，请检查配置后重试。',
      'The AI agent run failed.': 'Agent 运行失败，请稍后重试。',
      'Run cancelled.': '运行已取消。',
      'The operation stopped after reaching the tool-call limit.': '已达到工具调用次数上限。',
    }[message] ?? message
  )
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

function readStoredAutoRun() {
  try {
    return window.localStorage.getItem(AUTO_RUN_STORAGE_KEY) === 'true'
  } catch {
    return false
  }
}

function persistAutoRun(value: boolean) {
  try {
    window.localStorage.setItem(AUTO_RUN_STORAGE_KEY, String(value))
  } catch {
    // Ignore storage failures; the in-memory preference still works.
  }
}

export const useAiAgentStore = defineStore('ai-agent', () => {
  const settings = ref<AiAgentSettings | null>(null)
  const skills = ref<AiAgentSkill[]>([])
  const managedSkills = ref<AiAgentSkill[]>([])
  const mcpServers = ref<AiAgentMcpServer[]>([])
  const selectedSkillIds = ref<string[]>([])
  const conversations = ref<AiAgentConversation[]>([])
  const currentConnectionId = ref<string | null>(null)
  const selectedConversation = ref<AiAgentConversation | null>(null)
  const messages = ref<AiAgentMessage[]>([])
  const toolCalls = ref<AiAgentToolCall[]>([])
  const runSteps = ref<AiAgentRunStep[]>([])
  const usage = ref<AiAgentUsage | null>(null)
  const durationMs = ref<number | null>(null)
  const runStatus = ref<AiAgentRunStatus | 'idle' | 'running'>('idle')
  const lastRunInput = ref('')
  const lastRunAttachments = ref<AiAgentImageAttachment[]>([])
  const loadingSettings = ref(false)
  const loadingSkills = ref(false)
  const loadingManagedSkills = ref(false)
  const loadingMcpServers = ref(false)
  const loadingConversations = ref(false)
  const loadingConversation = ref(false)
  const running = ref(false)
  const streamingMessageId = ref<string | null>(null)
  const autoRun = ref(readStoredAutoRun())

  watch(autoRun, persistAutoRun)
  const runMode = ref<AiAgentRunMode>('agent')
  const activeRunId = ref<string | null>(null)
  const error = ref<string | null>(null)
  const skillsError = ref<string | null>(null)

  let listRequest = 0
  let detailRequest = 0
  let skillsRequest = 0
  let managedSkillsRequest = 0
  let runRequest = 0
  let runController: AbortController | null = null
  let runStartedAt: number | null = null
  let lastEventSequence = 0

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

  function setAutoRun(mode: boolean) {
    if (running.value) return false
    autoRun.value = mode
    persistAutoRun(mode)
    return true
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

  async function loadManagedSkills() {
    const request = ++managedSkillsRequest
    loadingManagedSkills.value = true
    try {
      const result = await aiAgentApi.listManagedSkills()
      if (request === managedSkillsRequest) managedSkills.value = result
      return managedSkills.value
    } finally {
      if (request === managedSkillsRequest) loadingManagedSkills.value = false
    }
  }

  async function refreshSkillsAfterManage() {
    await loadManagedSkills().catch(() => undefined)
    if (currentConnectionId.value) void loadSkills(currentConnectionId.value).catch(() => undefined)
  }

  async function getManagedSkill(id: number) {
    return aiAgentApi.getManagedSkill(id)
  }

  async function createManagedSkill(content: string) {
    const skill = await aiAgentApi.createManagedSkill(content)
    managedSkills.value = [...managedSkills.value, skill]
    await refreshSkillsAfterManage()
    return skill
  }

  async function updateManagedSkill(id: number, content: string) {
    const skill = await aiAgentApi.updateManagedSkill(id, content)
    managedSkills.value = managedSkills.value.map((item) => (item.id === skill.id ? skill : item))
    await refreshSkillsAfterManage()
    return skill
  }

  async function deleteManagedSkill(id: number) {
    await aiAgentApi.deleteManagedSkill(id)
    managedSkills.value = managedSkills.value.filter((skill) => skill.id !== `hostdeck:${id}`)
    selectedSkillIds.value = selectedSkillIds.value.filter((skillId) => skillId !== `hostdeck:${id}`)
    skills.value = skills.value.filter((skill) => skill.id !== `hostdeck:${id}`)
    await refreshSkillsAfterManage()
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

  function setRunMode(mode: AiAgentRunMode) {
    if (running.value) return
    runMode.value = mode
    if (mode === 'chat') selectedSkillIds.value = []
  }

  function resetForConnection(connectionId: string | null) {
    if (currentConnectionId.value === connectionId) return false
    abortRun()
    currentConnectionId.value = connectionId
    runMode.value = 'agent'
    conversations.value = []
    skills.value = []
    selectedSkillIds.value = []
    selectedConversation.value = null
    messages.value = []
    toolCalls.value = []
    runSteps.value = []
    usage.value = null
    durationMs.value = null
    runStatus.value = 'idle'
    lastRunInput.value = ''
    lastRunAttachments.value = []
    streamingMessageId.value = null
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
    runSteps.value = []
    usage.value = null
    durationMs.value = null
    runStatus.value = 'idle'
    lastRunInput.value = ''
    lastRunAttachments.value = []
    streamingMessageId.value = null
    error.value = null
    detailRequest += 1
    return conversation
  }

  async function selectConversation(id: string, connectionId: string) {
    resetForConnection(connectionId)
    if (running.value) return
    if (selectedConversation.value?.id === id) return
    if (loadingConversation.value) return
    const request = ++detailRequest
    loadingConversation.value = true
    error.value = null
    try {
      const result = await aiAgentApi.getConversation(id, connectionId)
      if (request !== detailRequest || currentConnectionId.value !== connectionId) return
      const restored = restoreConversation(result.messages)
      selectedConversation.value = result.conversation
      messages.value = restored.messages.slice(-MAX_MESSAGES)
      toolCalls.value = restored.tools.slice(-MAX_TOOL_CALLS)
      runSteps.value = restored.steps.slice(-MAX_TOOL_CALLS)
      usage.value = restored.usage
      durationMs.value = null
      runStatus.value = 'idle'
      streamingMessageId.value = null
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
      streamingMessageId.value = null
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

  function upsertRunStep(event: AiAgentRunEvent) {
    if (!event.stepId || event.sequence == null || !event.type || !event.status) return
    const existing = runSteps.value.find((step) => step.stepId === event.stepId)
    const content =
      event.event === 'message-reset'
        ? ''
        : existing?.content ??
          ('text' in event
            ? event.text
            : 'message' in event && typeof event.message === 'string'
              ? localizeRunMessage(event.message)
              : undefined)
    const step: AiAgentRunStep = {
      completedAt: event.completedAt,
      messageId: 'messageId' in event ? event.messageId : existing?.messageId,
      name: 'name' in event ? event.name : existing?.name,
      parentStepId: event.parentStepId ?? existing?.parentStepId,
      runId: event.runId ?? activeRunId.value ?? '',
      sequence: existing?.sequence ?? event.sequence,
      startedAt: existing?.startedAt ?? event.startedAt ?? Date.now(),
      status: event.status,
      stepId: event.stepId,
      summary: 'summary' in event ? event.summary : existing?.summary,
      type: event.type,
      callId: 'callId' in event ? event.callId : existing?.callId,
      arguments: 'arguments' in event ? event.arguments : existing?.arguments,
      content:
        event.event === 'message-reset'
          ? ''
          : existing?.content !== undefined && 'text' in event
          ? `${existing.content}${event.text}`
          : content,
    }
    runSteps.value = existing
      ? runSteps.value.map((item) => (item.stepId === step.stepId ? step : item))
      : [...runSteps.value, step].sort((a, b) => a.sequence - b.sequence)
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
        existing.result = event.result
        existing.status =
          event.status === 'expired'
            ? 'expired'
            : event.status === 'rejected' || existing.status === 'rejected'
              ? 'rejected'
              : event.success
                ? 'success'
                : 'error'
      } else {
        existing.status = 'running'
        if ('arguments' in event) existing.arguments = event.arguments
      }
      return
    }
    const nextTool: AiAgentToolCall = {
      approvalPending: event.event === 'approval-required',
      arguments: 'arguments' in event ? event.arguments : undefined,
      callId: event.callId,
      name: event.name,
      status:
        event.event === 'approval-required'
          ? 'pending'
          : event.event === 'tool-result'
            ? event.status === 'expired'
              ? 'expired'
              : event.status === 'rejected'
                ? 'rejected'
                : event.success
                  ? 'success'
                  : 'error'
            : 'running',
      submitting: false,
      summary: event.summary,
      result: event.event === 'tool-result' ? event.result : undefined,
    }
    toolCalls.value = [...toolCalls.value, nextTool].slice(-MAX_TOOL_CALLS)
  }

  function applyRunEvent(event: AiAgentRunEvent, assistant: AiAgentMessage) {
    if (event.event !== 'connected') {
      if (event.runId && activeRunId.value && event.runId !== activeRunId.value) return
      if (event.sequence != null && event.sequence <= lastEventSequence) return
      if (event.sequence != null) lastEventSequence = event.sequence
    }
    if (event.event === 'connected') {
      activeRunId.value = event.runId
      lastEventSequence = event.sequence ?? 0
    } else if (event.event === 'model-start' || event.event === 'model-end') {
      upsertRunStep(event)
    } else if (event.event === 'message-delta') {
      upsertRunStep(event)
      assistant.id = event.messageId
      streamingMessageId.value = event.messageId
      assistant.content += event.text
    } else if (event.event === 'message-reset') {
      upsertRunStep(event)
      assistant.id = event.messageId
      streamingMessageId.value = event.messageId
      assistant.content = ''
    } else if (
      event.event === 'tool-start' ||
      event.event === 'approval-required' ||
      event.event === 'tool-result'
    ) {
      upsertRunStep(event)
      upsertTool(event)
      if (event.event === 'approval-required' && autoRun.value) {
        void resolveApproval(event.callId, true).catch(() => undefined)
      }
    } else if (event.event === 'usage') {
      usage.value = event.usage
    } else if (event.event === 'done') {
      assistant.id = event.messageId
      finishRunTiming()
      runStatus.value = 'success'
    } else if (event.event === 'error') {
      upsertRunStep(event)
      error.value = localizeRunMessage(event.message)
      runStatus.value = event.status === 'cancelled' ? 'cancelled' : 'failed'
    } else if (event.event === 'run-end') {
      runStatus.value = event.status
      if (event.durationMs != null) durationMs.value = event.durationMs
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
    const activeMode = runMode.value
    const model = settings.value?.model
    const request = ++runRequest
    const controller = new AbortController()
    runController = controller
    running.value = true
    runStatus.value = 'running'
    lastRunInput.value = trimmedInput
    lastRunAttachments.value = [...attachments]
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
      streamingMessageId.value = streamedAssistant.id
      toolCalls.value = []
      runSteps.value = []
      usage.value = null
      durationMs.value = null
      runStartedAt = performance.now()
      error.value = null
      activeRunId.value = null
      lastEventSequence = 0
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
          activeMode,
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
          activeMode,
        )
      } else {
        await aiAgentApi.run(
          conversationId,
          connectionId,
          trimmedInput,
          runSkillIds,
          onEvent,
          controller.signal,
          undefined,
          [],
          activeMode,
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
        runStatus.value = 'failed'
      }
      if (!controller.signal.aborted) throw runError
      return false
    } finally {
      if (request === runRequest) {
        finishRunTiming()
        if (!completed) finishPendingTools('error')
        if (runStatus.value === 'running') {
          runStatus.value = controller.signal.aborted ? 'cancelled' : 'failed'
        }
        running.value = false
        streamingMessageId.value = null
        activeRunId.value = null
        lastEventSequence = 0
        runController = null
        selectedSkillIds.value = []
      }
    }
  }

  async function retryLastRun() {
    const connectionId = currentConnectionId.value
    if (
      !connectionId ||
      running.value ||
      (!lastRunInput.value && lastRunAttachments.value.length === 0)
    ) {
      return false
    }
    return startRun(lastRunInput.value, connectionId, [...lastRunAttachments.value])
  }

  function abortRun() {
    finishRunTiming()
    runRequest += 1
    runController?.abort()
    runController = null
    running.value = false
    if (runStatus.value === 'running') runStatus.value = 'cancelled'
    streamingMessageId.value = null
    activeRunId.value = null
    lastEventSequence = 0
    selectedSkillIds.value = []
    finishPendingTools('error')
  }

  async function cancelRun() {
    const runId = activeRunId.value
    const controller = runController
    if (!controller) return
    const cancellation = runId ? aiAgentApi.cancel(runId) : Promise.resolve()
    runStatus.value = 'cancelled'
    finishRunTiming()
    controller.abort()
    finishPendingTools('cancelled')
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

  function finishPendingTools(status: 'error' | 'rejected' | 'cancelled') {
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
    createManagedSkill,
    createConversation,
    currentConnectionId,
    deleteConversation,
    deleteManagedSkill,
    durationMs,
    error,
    hasPendingApproval,
    loadConversations,
    loadMcpServers,
    loadManagedSkills,
    loadModels,
    loadSkills,
    loadSettings,
    loadingConversation,
    loadingConversations,
    loadingMcpServers,
    loadingManagedSkills,
    loadingSettings,
    loadingSkills,
    messages,
    managedSkills,
    mcpServers,
    resetForConnection,
    resolveApproval,
    running,
    runMode,
    runStatus,
    retryLastRun,
    saveSettings,
    selectedSkillIds,
    selectedConversation,
    selectConversation,
    setAutoRun,
    settings,
    setSelectedSkillIds,
    setRunMode,
    skills,
    skillsError,
    startRun,
    streamingMessageId,
    testSettings,
    testMcpServer,
    toggleSkill,
    toolCalls,
    runSteps,
    createMcpServer,
    deleteMcpServer,
    updateMcpServer,
    updateManagedSkill,
    updateConversationTitle,
    getManagedSkill,
    usage,
  }
})
