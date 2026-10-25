<script setup lang="ts">
import { computed, h, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { useLocalStorage } from '@vueuse/core'
import type { MentionOption } from 'naive-ui'
import {
  ArrowUp,
  Bot,
  Check,
  CircleAlert,
  ChevronDown,
  Hand,
  ImagePlus,
  LoaderCircle,
  Menu,
  MessageCircle,
  PanelLeftClose,
  Pencil,
  PlugZap,
  Plus,
  Puzzle,
  RotateCcw,
  Search,
  Settings,
  ShieldCheck,
  Square,
  Trash2,
  Wrench,
  X,
} from '@lucide/vue'
import {
  aiAgentApi,
  type AiAgentConversation,
  type AiAgentImageAttachment,
  type AiAgentRunStep,
} from '@/api/ai-agent'
import { getUiApi } from '@/lib/ui'
import { MAX_SELECTED_SKILLS, useAiAgentStore } from '@/stores/ai-agent'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'
import AiAgentMarkdown from './components/AiAgentMarkdown.vue'
import AiAgentThinking from './components/AiAgentThinking.vue'
import AiAgentSkillPicker from './components/AiAgentSkillPicker.vue'
import AiAgentToolCall from './components/AiAgentToolCall.vue'
import AiAgentModelPicker from './components/AiAgentModelPicker.vue'
import {
  filesToImageAttachments,
  imageAttachmentSrc,
  MAX_IMAGE_ATTACHMENTS,
} from './components/image-attachments'
import { buildTimelineEntries, isToolEntry } from './components/timeline'

interface ConversationGroup {
  label: string
  conversations: AiAgentConversation[]
}

interface ModelOption {
  id: string
  key: string
  label: string
  provider: string
  hasCredentials: boolean
}

interface ModelGroup {
  models: ModelOption[]
  provider: string
}

const AGENT_SIDEBAR_WIDTH_STORAGE_KEY = 'host-deck:ai-agent:sidebar-width'
const DEFAULT_SIDEBAR_WIDTH = 240
const MIN_SIDEBAR_WIDTH = 200
const MAX_SIDEBAR_WIDTH = 420
// 容器（.n-modal-container / .n-drawer-container）由 LazyTeleport 常驻 DOM，
// 必须匹配真正的内容节点并校验可见性，否则打开过一次弹窗后 Esc 会永久失效。
const ESCAPE_BLOCKING_SELECTOR = [
  '.n-modal-container .n-modal',
  '.n-drawer-container .n-drawer',
  '.n-image-preview-overlay',
].join(', ')

const props = defineProps<{ windowId?: string }>()

const agentStore = useAiAgentStore()
const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const sshStore = useSshStore()
const sessionConnectionIds = new Set<string>()
const {
  autoRun,
  conversations,
  durationMs,
  error,
  loadingConversation,
  loadingConversations,
  messages,
  running,
  runMode,
  selectedConversation,
  selectedSkillIds,
  settings,
  skills,
  streamingMessageId,
  toolCalls,
  runSteps,
  runStatus,
  usage,
} = storeToRefs(agentStore)

const rootElement = ref<HTMLElement>()
const compactLayout = ref(false)
const containerWidth = ref(0)
const sidebarOpen = ref(true)
const sidebarWidth = useLocalStorage(AGENT_SIDEBAR_WIDTH_STORAGE_KEY, DEFAULT_SIDEBAR_WIDTH)
const sidebarResizing = ref(false)
const resizeWidth = ref<number | null>(null)
const addMenuOpen = ref(false)
const permissionMenuOpen = ref(false)
const modelPickerOpen = ref(false)
const runElapsedSeconds = ref(0)
const query = ref('')
const input = ref('')
const imageInput = ref<HTMLInputElement>()
const imageAttachments = ref<AiAgentImageAttachment[]>([])
const messageScroller = ref<HTMLElement>()
const followOutput = ref(true)
const showScrollButton = ref(false)
const editingConversationId = ref<string | null>(null)
const editingTitle = ref('')
const savingConversationId = ref<string | null>(null)
const switchingModel = ref(false)

const hostLabel = computed(() => {
  const host = sshStore.host.trim() || '当前主机'
  return sshStore.username ? `${sshStore.username}@${host}` : host
})

const filteredConversations = computed(() => {
  const keyword = query.value.trim().toLocaleLowerCase()
  if (!keyword) return conversations.value
  return conversations.value.filter((conversation) =>
    (conversation.title || '新对话').toLocaleLowerCase().includes(keyword),
  )
})

const conversationGroups = computed<ConversationGroup[]>(() => {
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const weekAgo = today.getTime() - 6 * 24 * 60 * 60 * 1000
  const groups: ConversationGroup[] = [
    { conversations: [], label: '今天' },
    { conversations: [], label: '最近 7 天' },
    { conversations: [], label: '更早' },
  ]

  for (const conversation of filteredConversations.value) {
    const value = conversation.updatedAt
    const timestamp =
      typeof value === 'number'
        ? value
        : /^\d+$/.test(value)
          ? Number(value)
          : new Date(value).getTime()
    if (timestamp >= today.getTime()) groups[0]!.conversations.push(conversation)
    else if (timestamp >= weekAgo) groups[1]!.conversations.push(conversation)
    else groups[2]!.conversations.push(conversation)
  }

  return groups.filter((group) => group.conversations.length > 0)
})

const canSend = computed(() =>
  Boolean(
    (input.value.trim() || imageAttachments.value.length > 0) &&
    sshStore.connectionId &&
    settings.value?.hasCredentials &&
    !running.value,
  ),
)

const skillMentionOptions = computed<MentionOption[]>(() =>
  skills.value.map((skill) => ({
    description: skill.description,
    disabled:
      selectedSkillIds.value.length >= MAX_SELECTED_SKILLS &&
      !selectedSkillIds.value.includes(skill.id),
    label: `${skill.name} · ${skill.source}`,
    skillId: skill.id,
    source: skill.source,
    value: skill.name,
  })),
)

const selectedSkills = computed(() => {
  const selectedIds = new Set(selectedSkillIds.value)
  return skills.value.filter((skill) => selectedIds.has(skill.id))
})

const timelineEntries = computed(() => buildTimelineEntries(messages.value, runSteps.value))

const toolsByCallId = computed(() => new Map(toolCalls.value.map((tool) => [tool.callId, tool])))

function toolForStep(step: AiAgentRunStep) {
  return step.callId ? toolsByCallId.value.get(step.callId) : undefined
}

// 连续的工具调用共用一个 Agent 标题，避免每个卡片重复一次角色标签。
function isToolGroupStart(index: number) {
  return !isToolEntry(timelineEntries.value[index - 1])
}

const currentPhase = computed(() => {
  if (!running.value) return '已完成'
  if (toolCalls.value.some((tool) => tool.approvalPending)) return '等待授权'
  if (toolCalls.value.some((tool) => tool.status === 'running')) return '执行工具'
  const latestStep = [...runSteps.value].sort((a, b) => b.sequence - a.sequence)[0]
  return latestStep?.type === 'tool' &&
    ['success', 'failed', 'rejected', 'expired'].includes(latestStep.status)
    ? '整理结果'
    : '分析中'
})

const runStatusLabel = computed(() => {
  switch (runStatus.value) {
    case 'success':
      return '已完成'
    case 'limit':
      return '本轮预算用尽'
    case 'failed':
      return '运行失败'
    case 'cancelled':
      return '已取消'
    case 'expired':
      return '已过期'
    default:
      return ''
  }
})

const runToolCount = computed(() => toolCalls.value.length)

const enabledMcpServers = computed(() => agentStore.mcpServers.filter((server) => server.enabled))
const modelOptions = computed<ModelOption[]>(() =>
  (settings.value?.providers ?? []).flatMap((provider) =>
    provider.models.map((model) => ({
      id: model.id,
      key: `${provider.id}:${model.id}`,
      label: model.name || model.id,
      provider: provider.id,
      hasCredentials: provider.hasCredentials,
    })),
  ),
)
const modelGroups = computed<ModelGroup[]>(() => {
  const groups = new Map<string, ModelOption[]>()
  for (const model of modelOptions.value) {
    const models = groups.get(model.provider) ?? []
    models.push(model)
    groups.set(model.provider, models)
  }
  return [...groups].map(([provider, models]) => ({ models, provider }))
})
const activeModelName = computed(() => {
  const activeProvider = settings.value?.providers.find(
    (provider) => provider.id === settings.value?.provider,
  )
  const activeModel = activeProvider?.models.find((model) => model.id === settings.value?.model)
  return activeModel?.name || settings.value?.model || '选择模型'
})

let settingsRequestId = 0

function openSettings(section: 'mcp' | 'model' | 'skills' | 'tools' = 'model') {
  const windowProps = {
    initialTab: section,
    tabRequestId: ++settingsRequestId,
  }
  const settingsWindowId = desktopStore.openWindow('ai-agent-settings', windowProps, {
    parentId: props.windowId,
  })
  if (settingsWindowId) desktopStore.updateWindowProps(settingsWindowId, windowProps)
}

function selectRunMode(mode: boolean) {
  if (running.value || !sshStore.connectionId) return
  agentStore.setAutoRun(mode)
  permissionMenuOpen.value = false
}

function selectAiMode(mode: 'chat' | 'agent') {
  if (!sshStore.connectionId || running.value) return
  agentStore.setRunMode(mode)
}

function closeSidebarOnNarrowScreen() {
  if (compactLayout.value) sidebarOpen.value = false
}

const maxSidebarWidth = computed(() => {
  const width = containerWidth.value
  if (!width) return MAX_SIDEBAR_WIDTH
  return Math.max(MIN_SIDEBAR_WIDTH, Math.min(MAX_SIDEBAR_WIDTH, width - 320))
})

const normalizedSidebarWidth = computed(() => {
  const width = Number(sidebarWidth.value)
  const value = Number.isFinite(width) ? width : DEFAULT_SIDEBAR_WIDTH
  return Math.min(maxSidebarWidth.value, Math.max(MIN_SIDEBAR_WIDTH, value))
})

const effectiveSidebarWidth = computed(() => {
  const width = resizeWidth.value ?? normalizedSidebarWidth.value
  return Math.min(maxSidebarWidth.value, Math.max(MIN_SIDEBAR_WIDTH, width))
})

let resizeStartClientX = 0
let resizeStartWidth = 0
let previousBodyCursor = ''
let previousBodyUserSelect = ''

function handleSidebarResize(event: PointerEvent) {
  if (!sidebarResizing.value) return
  const width = resizeStartWidth + event.clientX - resizeStartClientX
  // 拖到最小宽度时收起侧边栏
  if (width <= MIN_SIDEBAR_WIDTH) {
    resizeWidth.value = null
    stopSidebarResize()
    sidebarOpen.value = false
    return
  }
  resizeWidth.value = Math.min(maxSidebarWidth.value, Math.round(width))
}

function stopSidebarResize() {
  if (!sidebarResizing.value) return
  sidebarResizing.value = false
  window.removeEventListener('pointermove', handleSidebarResize)
  window.removeEventListener('pointerup', stopSidebarResize)
  window.removeEventListener('pointercancel', stopSidebarResize)
  document.body.style.cursor = previousBodyCursor
  document.body.style.userSelect = previousBodyUserSelect
  if (resizeWidth.value !== null) {
    sidebarWidth.value = resizeWidth.value
    resizeWidth.value = null
  }
}

function startSidebarResize(event: PointerEvent) {
  if (event.button !== 0 || compactLayout.value) return
  event.preventDefault()
  event.stopPropagation()
  sidebarResizing.value = true
  resizeStartClientX = event.clientX
  resizeStartWidth = normalizedSidebarWidth.value
  resizeWidth.value = resizeStartWidth
  previousBodyCursor = document.body.style.cursor
  previousBodyUserSelect = document.body.style.userSelect
  document.body.style.cursor = 'col-resize'
  document.body.style.userSelect = 'none'
  window.addEventListener('pointermove', handleSidebarResize)
  window.addEventListener('pointerup', stopSidebarResize)
  window.addEventListener('pointercancel', stopSidebarResize)
}

function handleSidebarResizeKey(event: KeyboardEvent) {
  const delta = event.key === 'ArrowLeft' ? -16 : event.key === 'ArrowRight' ? 16 : 0
  if (!delta) return
  event.preventDefault()
  sidebarWidth.value = Math.min(
    maxSidebarWidth.value,
    Math.max(MIN_SIDEBAR_WIDTH, normalizedSidebarWidth.value + delta),
  )
}

/** naive-ui 用 v-show 隐藏已关闭的覆盖层，因此按 display/visibility 判断可见性 */
function isElementVisible(element: Element) {
  let current: Element | null = element
  while (current) {
    if (current.hasAttribute('hidden') || current.getAttribute('aria-hidden') === 'true') {
      return false
    }
    const style = window.getComputedStyle(current)
    if (style.display === 'none' || style.visibility === 'hidden') return false
    current = current.parentElement
  }
  return true
}

/** 弹窗、抽屉、图片预览等覆盖层自身响应 Esc，需要让给它们 */
function isOverlayOpen() {
  return [...document.querySelectorAll(ESCAPE_BLOCKING_SELECTOR)].some(isElementVisible)
}

/** 焦点可能落在 body 等公共节点上，按事件目标归属判断是否需要处理 */
function ownsKeyboardTarget(target: EventTarget | null) {
  const root = rootElement.value
  if (!root) return false
  if (!(target instanceof Node)) return true
  if (root.contains(target)) return true
  return target === document.body || target === document.documentElement
}

function closeComposerMentionMenu() {
  const menu = document.querySelector('.n-mention-menu')
  if (!menu || !isElementVisible(menu)) return false
  // 失焦会关闭 @ 提及菜单，避免同一次 Esc 既关菜单又中断任务
  rootElement.value?.querySelector<HTMLTextAreaElement>('.agent-composer-input textarea')?.blur()
  return true
}

function handleWindowKeydown(event: KeyboardEvent) {
  if (event.isComposing || event.keyCode === 229) return
  if (event.key !== 'Escape' && event.code !== 'Escape') return
  // 正在编辑对话标题时由输入框自己处理
  if (editingConversationId.value) return
  // 模型/权限浮层的焦点在 teleport 后的浮层里，不受窗口归属限制
  if (modelPickerOpen.value || addMenuOpen.value || permissionMenuOpen.value) {
    modelPickerOpen.value = false
    addMenuOpen.value = false
    permissionMenuOpen.value = false
    event.preventDefault()
    return
  }
  if (!ownsKeyboardTarget(event.target)) return
  if (closeComposerMentionMenu()) {
    event.preventDefault()
    return
  }
  if (isOverlayOpen()) return
  if (!running.value) return
  event.preventDefault()
  void stop()
}

async function loadForConnection(connectionId: string) {
  try {
    await Promise.all([
      agentStore.loadSettings(),
      agentStore.loadModelCatalog().catch(() => undefined),
      agentStore.loadMcpServers(),
      agentStore.loadConversations(connectionId),
      agentStore.loadSkills(connectionId),
    ])
  } catch {
    // The store exposes the actionable error in the workspace.
  }
}

async function newConversation() {
  const connectionId = sshStore.connectionId
  if (!connectionId || running.value) return
  try {
    await agentStore.createConversation(connectionId)
    input.value = ''
    imageAttachments.value = []
    closeSidebarOnNarrowScreen()
  } catch (requestError) {
    getUiApi().message.error(
      requestError instanceof Error ? requestError.message : '创建对话失败。',
    )
  }
}

async function openConversation(id: string) {
  const connectionId = sshStore.connectionId
  if (!connectionId || loadingConversation.value || selectedConversation.value?.id === id) {
    return
  }
  try {
    await agentStore.selectConversation(id, connectionId)
    input.value = ''
    imageAttachments.value = []
    closeSidebarOnNarrowScreen()
  } catch {
    // The store keeps the detail error visible in context.
  }
}

function editConversation(conversation: AiAgentConversation) {
  editingConversationId.value = conversation.id
  editingTitle.value = conversation.title || '新对话'
  void nextTick(() => {
    document.querySelector<HTMLInputElement>('.agent-history-title-input')?.select()
  })
}

function cancelEditingConversation() {
  editingConversationId.value = null
  editingTitle.value = ''
}

async function saveConversationTitle(conversation: AiAgentConversation) {
  if (
    editingConversationId.value !== conversation.id ||
    savingConversationId.value === conversation.id
  ) {
    return
  }
  const connectionId = sshStore.connectionId
  const title = editingTitle.value.trim()
  if (!connectionId) return
  if (!title) {
    getUiApi().message.warning('对话标题不能为空。')
    return
  }
  if (title === (conversation.title || '新对话')) {
    cancelEditingConversation()
    return
  }
  savingConversationId.value = conversation.id
  try {
    await agentStore.updateConversationTitle(conversation.id, title, connectionId)
    cancelEditingConversation()
  } catch (requestError) {
    getUiApi().message.error(
      requestError instanceof Error ? requestError.message : '修改对话标题失败。',
    )
  } finally {
    savingConversationId.value = null
  }
}

function removeConversation(conversation: AiAgentConversation) {
  const connectionId = sshStore.connectionId
  if (!connectionId) return
  const dialog = getUiApi().dialog.warning({
    title: '删除对话',
    content: `确认删除“${conversation.title || '新对话'}”？此操作无法撤销。`,
    positiveText: '删除',
    negativeText: '取消',
    onPositiveClick: async () => {
      dialog.loading = true
      try {
        await agentStore.deleteConversation(conversation.id, connectionId)
      } catch (requestError) {
        getUiApi().message.error(
          requestError instanceof Error ? requestError.message : '删除对话失败。',
        )
      } finally {
        dialog.loading = false
      }
    },
  })
}

async function send() {
  const connectionId = sshStore.connectionId
  const value = input.value.trim()
  const attachments = [...imageAttachments.value]
  if (!connectionId || (!value && attachments.length === 0) || running.value) return
  input.value = ''
  imageAttachments.value = []
  try {
    await agentStore.startRun(value, connectionId, attachments)
  } catch {
    // Keep the failed prompt in history and show the store error above the composer.
  }
}

async function addImageFiles(files: File[]) {
  if (running.value || files.length === 0) return
  try {
    const result = await filesToImageAttachments(files, imageAttachments.value)
    imageAttachments.value = result.attachments
    if (result.rejected.length) getUiApi().message.warning(result.rejected.join('；'))
  } catch (readError) {
    getUiApi().message.error(readError instanceof Error ? readError.message : '读取图片失败。')
  }
}

function selectImages(event: Event) {
  const target = event.currentTarget as HTMLInputElement
  void addImageFiles(Array.from(target.files ?? []))
  target.value = ''
}

function handlePaste(event: ClipboardEvent) {
  const imageFiles = Array.from(event.clipboardData?.items ?? [])
    .filter((item) => item.kind === 'file' && item.type.startsWith('image/'))
    .map((item) => item.getAsFile())
    .filter((file): file is File => file !== null)
  if (imageFiles.length === 0) return
  event.preventDefault()
  void addImageFiles(imageFiles)
}

function removeImage(index: number) {
  if (running.value) return
  imageAttachments.value = imageAttachments.value.filter((_, itemIndex) => itemIndex !== index)
}

function pickComposerImages() {
  addMenuOpen.value = false
  imageInput.value?.click()
}

function selectAiModeFromMenu(mode: 'chat' | 'agent') {
  selectAiMode(mode)
  addMenuOpen.value = false
}

function openComposerSettings(section: 'mcp' | 'tools') {
  addMenuOpen.value = false
  openSettings(section)
}

async function switchModel(provider: string, model: string) {
  if (
    (provider === settings.value?.provider && model === settings.value?.model) ||
    switchingModel.value ||
    running.value
  )
    return true
  switchingModel.value = true
  try {
    await agentStore.saveSettings({ provider, model })
    return true
  } catch (requestError) {
    getUiApi().message.error(
      requestError instanceof Error ? requestError.message : '切换模型失败。',
    )
    return false
  } finally {
    switchingModel.value = false
  }
}

function selectModel(provider: string, model: string) {
  void switchModel(provider, model)
}

function handleComposerKeydown(event: KeyboardEvent) {
  if (event.defaultPrevented || event.isComposing) return
  // 输入框为空时按 “/” 直接打开指令菜单，与占位提示保持一致。
  if (event.key === '/' && !event.shiftKey && !input.value.trim() && !running.value) {
    event.preventDefault()
    addMenuOpen.value = true
    return
  }
  if (event.key !== 'Enter' || event.shiftKey) return
  event.preventDefault()
  void send()
}

function filterSkillMention(pattern: string, option: MentionOption) {
  const keyword = pattern.toLocaleLowerCase()
  return [option.value, option.label, option.description, option.source].some(
    (value) => typeof value === 'string' && value.toLocaleLowerCase().includes(keyword),
  )
}

function selectSkillMention(option: MentionOption) {
  if (typeof option.skillId !== 'string') return
  agentStore.setSelectedSkillIds([...selectedSkillIds.value, option.skillId])
  if (typeof option.value === 'string') {
    const skillName = option.value
    void nextTick(() => removeMentionText(skillName))
  }
}

function removeMentionText(skillName: string) {
  const mention = `@${skillName}`
  const index = input.value.lastIndexOf(mention)
  if (index < 0) return
  const mentionEnd = index + mention.length
  const removeEnd = input.value[mentionEnd] === ' ' ? mentionEnd + 1 : mentionEnd
  input.value = `${input.value.slice(0, index)}${input.value.slice(removeEnd)}`
}

function removeSelectedSkill(skillId: string) {
  agentStore.setSelectedSkillIds(selectedSkillIds.value.filter((id) => id !== skillId))
}

function renderSkillMentionLabel(option: MentionOption) {
  return h('div', { class: 'agent-skill-mention-option' }, [
    h(Puzzle, { class: 'agent-skill-mention-icon', size: 14 }),
    h('span', { class: 'agent-skill-mention-name' }, String(option.value ?? '')),
    h('small', { class: 'agent-skill-mention-source' }, String(option.source ?? '')),
  ])
}

async function stop() {
  try {
    await agentStore.cancelRun()
  } catch (requestError) {
    getUiApi().message.error(
      requestError instanceof Error ? requestError.message : '停止任务失败。',
    )
  }
}

async function resolveApproval(callId: string, approved: boolean) {
  try {
    await agentStore.resolveApproval(callId, approved)
  } catch {
    // The store error remains visible while the stream continues.
  }
}

function handleMessageScroll() {
  const element = messageScroller.value
  if (!element) return
  const nearBottom = element.scrollHeight - element.scrollTop - element.clientHeight < 96
  followOutput.value = nearBottom
  showScrollButton.value = !nearBottom
}

let scrollFrame: number | undefined
let forceScroll = false

function scrollToLatest(force = false) {
  forceScroll ||= force
  if (scrollFrame !== undefined) return
  void nextTick(() => {
    if (scrollFrame !== undefined || !rootElement.value) return
    scrollFrame = window.requestAnimationFrame(() => {
      scrollFrame = undefined
      const shouldScroll = forceScroll || followOutput.value
      forceScroll = false
      const element = messageScroller.value
      if (!element || !shouldScroll) return
      element.scrollTop = element.scrollHeight
      showScrollButton.value = false
    })
  })
}

function handleBeforeUnload() {
  void agentStore.cancelRun()
}

watch(
  () => sshStore.connectionId,
  (connectionId) => {
    if (connectionId) {
      input.value = ''
      imageAttachments.value = []
      sessionConnectionIds.add(connectionId)
      void loadForConnection(connectionId)
    } else agentStore.resetForConnection(null)
  },
  { immediate: true },
)

function focusComposer() {
  rootElement.value?.querySelector<HTMLTextAreaElement>('.agent-composer-input textarea')?.focus()
}

watch(
  () => desktopStore.activeWindowId,
  (activeWindowId) => {
    if (props.windowId && activeWindowId === props.windowId) {
      window.setTimeout(focusComposer, 16)
    }
  },
)

watch(
  () => [
    messages.value.length,
    toolCalls.value.map((tool) => `${tool.callId}:${tool.status}`).join(','),
    runSteps.value.length,
    running.value,
  ],
  () => scrollToLatest(),
  { flush: 'post' },
)

let runElapsedTimer: number | undefined

function stopRunElapsedTimer() {
  if (runElapsedTimer === undefined) return
  window.clearInterval(runElapsedTimer)
  runElapsedTimer = undefined
}

// 运行中在输入框上方显示已用时长，与运行阶段一起提示当前进度。
watch(running, (value) => {
  stopRunElapsedTimer()
  runElapsedSeconds.value = 0
  if (!value) return
  const startedAt = performance.now()
  runElapsedTimer = window.setInterval(() => {
    runElapsedSeconds.value = Math.floor((performance.now() - startedAt) / 1000)
  }, 1000)
})

onMounted(() => {
  if (typeof ResizeObserver !== 'undefined') {
    resizeObserver = new ResizeObserver(([entry]) => {
      const width = entry?.contentRect.width ?? 760
      containerWidth.value = width
      const compact = width < 760
      if (compact !== compactLayout.value) {
        compactLayout.value = compact
        sidebarOpen.value = !compact
      }
    })
    if (rootElement.value) resizeObserver.observe(rootElement.value)
  }
  window.addEventListener('beforeunload', handleBeforeUnload)
  window.addEventListener('keydown', handleWindowKeydown)
  if (props.windowId && desktopStore.activeWindowId === props.windowId) {
    void nextTick(focusComposer)
  }
})

onBeforeUnmount(() => {
  if (scrollFrame !== undefined) window.cancelAnimationFrame(scrollFrame)
  resizeObserver?.disconnect()
  stopRunElapsedTimer()
  stopSidebarResize()
  window.removeEventListener('beforeunload', handleBeforeUnload)
  window.removeEventListener('keydown', handleWindowKeydown)
  void (async () => {
    try {
      await agentStore.cancelRun()
    } finally {
      await Promise.allSettled(
        [...sessionConnectionIds].map((connectionId) => aiAgentApi.closeSession(connectionId)),
      )
    }
  })().catch(() => undefined)
})

let resizeObserver: ResizeObserver | undefined
</script>

<template>
  <div
    ref="rootElement"
    class="ai-agent-root"
    :class="[
      settingsStore.isDark ? 'ai-agent-dark' : 'ai-agent-light',
      { 'ai-agent-sidebar-open': sidebarOpen, 'ai-agent-sidebar-resizing': sidebarResizing },
    ]"
    :style="{ '--agent-sidebar-width': `${effectiveSidebarWidth}px` }"
  >
    <button
      v-if="sidebarOpen"
      type="button"
      class="agent-sidebar-backdrop"
      aria-label="关闭侧边栏"
      @click="sidebarOpen = false"
    />

    <aside class="agent-sidebar" aria-label="对话侧边栏">
      <div class="agent-sidebar-title">
        <div class="flex min-w-0 items-center gap-2.5">
          <img src="@/assets/ai-agent.svg" alt="" class="h-7 w-7 rounded-[8px]" />
          <strong class="truncate text-[15px]">AI Agent</strong>
        </div>
        <button
          type="button"
          class="agent-icon-button"
          aria-label="收起侧边栏"
          @click="sidebarOpen = false"
        >
          <PanelLeftClose :size="17" />
        </button>
      </div>

      <label class="agent-search">
        <Search :size="14" />
        <input v-model="query" type="search" placeholder="搜索对话" aria-label="搜索对话" />
      </label>

      <div class="agent-history-header">
        <span>对话</span>
        <button
          type="button"
          class="agent-history-new"
          aria-label="新建对话"
          title="新建对话"
          :disabled="!sshStore.connectionId || running"
          @click="newConversation"
        >
          <Plus :size="18" />
        </button>
      </div>

      <div class="agent-history app-scrollbar app-scrollbar-compact">
        <div v-if="loadingConversations" class="agent-sidebar-state">正在加载对话…</div>
        <div v-else-if="conversationGroups.length === 0" class="agent-sidebar-state">
          {{ query ? '没有匹配的对话' : '还没有对话' }}
        </div>
        <div v-else>
          <section
            v-for="group in conversationGroups"
            :key="group.label"
            class="agent-history-group"
          >
            <h2>{{ group.label }}</h2>
            <div
              v-for="conversation in group.conversations"
              :key="conversation.id"
              class="agent-history-row"
              :class="{ 'agent-history-row-active': selectedConversation?.id === conversation.id }"
            >
              <button
                v-if="editingConversationId !== conversation.id"
                type="button"
                class="agent-history-open"
                :disabled="running"
                @click="openConversation(conversation.id)"
              >
                <span>{{ conversation.title || '新对话' }}</span>
              </button>
              <input
                v-else
                v-model="editingTitle"
                class="agent-history-title-input"
                type="text"
                maxlength="100"
                aria-label="对话标题"
                :disabled="savingConversationId === conversation.id"
                @blur="saveConversationTitle(conversation)"
                @keydown.enter.prevent="($event.currentTarget as HTMLInputElement).blur()"
                @keydown.esc.prevent="cancelEditingConversation"
              />
              <button
                v-if="editingConversationId !== conversation.id"
                type="button"
                class="agent-history-edit"
                :disabled="running"
                :aria-label="`修改 ${conversation.title || '新对话'} 的标题`"
                @click="editConversation(conversation)"
              >
                <Pencil :size="13" />
              </button>
              <button
                v-if="editingConversationId !== conversation.id"
                type="button"
                class="agent-history-delete"
                :disabled="running"
                :aria-label="`删除 ${conversation.title || '新对话'}`"
                @click="removeConversation(conversation)"
              >
                <Trash2 :size="13" />
              </button>
            </div>
          </section>
        </div>
      </div>
    </aside>

    <div
      v-if="sidebarOpen && !compactLayout"
      class="agent-sidebar-resizer"
      :class="{ 'agent-sidebar-resizer-active': sidebarResizing }"
      role="separator"
      tabindex="0"
      aria-label="调整对话侧边栏宽度，拖到最小宽度以下可收起"
      aria-orientation="vertical"
      :aria-valuemin="MIN_SIDEBAR_WIDTH"
      :aria-valuemax="maxSidebarWidth"
      :aria-valuenow="normalizedSidebarWidth"
      :style="{ left: `${effectiveSidebarWidth}px` }"
      @pointerdown="startSidebarResize"
      @keydown="handleSidebarResizeKey"
    />

    <main class="agent-main">
      <header class="agent-header">
        <button
          type="button"
          class="agent-icon-button"
          :aria-label="sidebarOpen ? '收起侧边栏' : '展开侧边栏'"
          @click="sidebarOpen = !sidebarOpen"
        >
          <Menu :size="18" />
        </button>
        <div class="min-w-0 flex-1">
          <div class="truncate text-[12px] font-medium">
            {{ selectedConversation?.title || 'AI Agent' }}
          </div>
          <div class="flex min-w-0 items-center gap-1.5 text-[10px] opacity-55">
            <span class="truncate">{{ hostLabel }}</span>
            <span>·</span>
            <span class="truncate"
              >{{ settings?.provider === 'custom' ? '自定义' : settings?.provider }} ·
              {{ settings?.model || '未配置模型' }}</span
            >
          </div>
        </div>
        <button
          type="button"
          class="agent-icon-button"
          aria-label="模型设置"
          @click="openSettings()"
        >
          <Settings :size="17" />
        </button>
      </header>

      <div ref="messageScroller" class="agent-messages app-scrollbar" @scroll="handleMessageScroll">
        <div v-if="loadingConversation" class="agent-loading">
          <NSpin size="small" /> 正在加载对话
        </div>
        <div v-else-if="messages.length === 0 && toolCalls.length === 0" class="agent-empty-state">
          <div class="agent-empty-mark"><Bot :size="27" /></div>
          <h1>{{ runMode === 'agent' ? '我们要维护什么？' : '今天想聊些什么？' }}</h1>
        </div>
        <div v-else class="agent-transcript">
          <template
            v-for="(entry, index) in timelineEntries"
            :key="entry.kind === 'message' ? entry.message.id : entry.step.stepId"
          >
            <article
              v-if="entry.kind === 'message'"
              class="agent-message"
              :class="`agent-message-${entry.message.role}`"
            >
              <div v-if="entry.message.role !== 'user'" class="agent-message-role">
                <Bot v-if="entry.message.role === 'assistant'" :size="14" />
                <CircleAlert v-else-if="entry.message.role === 'error'" :size="14" />
                <Wrench v-else :size="14" />
                {{
                  entry.message.role === 'assistant'
                    ? 'Agent'
                    : entry.message.role === 'error'
                      ? '运行状态'
                      : entry.message.role
                }}
              </div>
              <div v-if="entry.message.role === 'user'" class="agent-message-user-wrap">
                <div class="agent-message-user-bubble">
                  <div v-if="entry.message.content" class="agent-message-content">
                    {{ entry.message.content }}
                  </div>
                  <div v-if="entry.message.attachments?.length" class="agent-message-images">
                    <NImage
                      v-for="(attachment, index) in entry.message.attachments"
                      :key="`${entry.message.id}-${index}`"
                      :src="imageAttachmentSrc(attachment)"
                      :alt="attachment.name || '上传的图片'"
                      object-fit="cover"
                      lazy
                    />
                  </div>
                </div>
              </div>
              <AiAgentThinking
                v-if="entry.message.role === 'assistant' && entry.message.thinking"
                :content="entry.message.thinking"
                @rendered="scrollToLatest()"
              />
              <AiAgentMarkdown
                v-if="entry.message.content && entry.message.role === 'assistant'"
                :content="entry.message.content"
                :streaming="running && entry.message.id === streamingMessageId"
                @rendered="scrollToLatest()"
              />
              <div
                v-if="
                  entry.message.content &&
                  entry.message.role !== 'assistant' &&
                  entry.message.role !== 'user'
                "
                class="agent-message-content"
              >
                {{ entry.message.content }}
              </div>
              <div
                v-else-if="
                  entry.message.role === 'assistant' &&
                  entry.message.id === streamingMessageId &&
                  !entry.message.content &&
                  !entry.message.thinking
                "
                class="agent-thinking"
                aria-label="Agent 正在思考"
              >
                <span /><span /><span />
              </div>
            </article>
            <div
              v-else-if="entry.step.type === 'model'"
              class="agent-message agent-message-assistant"
            >
              <div class="agent-message-role"><Bot :size="14" /> Agent</div>
              <AiAgentThinking
                v-if="entry.step.thinking"
                :content="entry.step.thinking"
                :running="running && entry.step.status === 'running' && entry.step.thinkingRunning"
                @rendered="scrollToLatest()"
              />
              <AiAgentMarkdown
                v-if="entry.step.content"
                :content="entry.step.content"
                :streaming="running && entry.step.status === 'running'"
                @rendered="scrollToLatest()"
              />
              <div
                v-else-if="running && entry.step.status === 'running' && !entry.step.thinking"
                class="agent-thinking"
                aria-label="Agent 正在思考"
              >
                <span /><span /><span />
              </div>
            </div>
            <div
              v-else-if="entry.step.type === 'error'"
              class="agent-message agent-message-error"
              role="alert"
            >
              <div class="agent-message-role"><CircleAlert :size="14" /> 运行状态</div>
              <div v-if="entry.step.content" class="agent-message-content">
                {{ entry.step.content }}
              </div>
            </div>
            <div
              v-else-if="entry.step.type === 'summary'"
              class="agent-message agent-message-assistant"
            >
              <div class="agent-message-role"><Bot :size="14" /> Agent</div>
              <AiAgentMarkdown v-if="entry.step.content" :content="entry.step.content" />
            </div>
            <div
              v-else-if="
                (entry.step.type === 'tool' || entry.step.type === 'approval') &&
                toolForStep(entry.step)
              "
              class="agent-tools"
              :class="{ 'agent-tools-continuation': !isToolGroupStart(index) }"
            >
              <div v-if="isToolGroupStart(index)" class="agent-message-role">
                <Bot :size="14" /> Agent
              </div>
              <AiAgentToolCall
                :tool="toolForStep(entry.step)!"
                @approve="resolveApproval($event, true)"
                @reject="resolveApproval($event, false)"
              />
            </div>
          </template>
          <div
            v-if="runStatusLabel || usage?.totalTokens != null || durationMs != null"
            class="agent-usage"
          >
            <span v-if="runStatusLabel" :class="`agent-usage-status agent-usage-${runStatus}`">
              {{ runStatusLabel }}
            </span>
            <span v-if="runToolCount">工具调用 {{ runToolCount }} 次</span>
            <span v-if="usage?.promptTokens != null">
              输入 {{ usage.promptTokens.toLocaleString() }} tokens
            </span>
            <span v-if="usage?.responseTokens != null">
              输出 {{ usage.responseTokens.toLocaleString() }} tokens
            </span>
            <span v-if="usage?.totalTokens != null">
              本次使用 {{ usage.totalTokens.toLocaleString() }} tokens
            </span>
            <span v-if="durationMs != null">执行耗时 {{ (durationMs / 1000).toFixed(1) }} 秒</span>
          </div>
        </div>
      </div>

      <footer class="agent-composer-area">
        <div v-if="error" class="agent-error" role="alert">
          <span>{{ error }}</span>
          <button
            v-if="runStatus === 'failed' || runStatus === 'cancelled'"
            type="button"
            class="agent-error-retry"
            @click="void agentStore.retryLastRun().catch(() => undefined)"
          >
            <RotateCcw :size="12" />
            重试
          </button>
        </div>
        <button
          v-if="settings && !settings.hasCredentials"
          type="button"
          class="agent-configure"
          @click="openSettings()"
        >
          {{
            settings?.provider === 'openai-codex'
              ? '登录 OpenAI Codex 后开始对话'
              : '配置 API Key 后开始对话'
          }}
        </button>
        <div v-if="running" class="agent-run-phase" aria-live="polite">
          <LoaderCircle :size="13" class="agent-run-phase-spinner" />
          <span>{{ currentPhase }}，用时 {{ runElapsedSeconds }} 秒…</span>
        </div>
        <button
          v-if="showScrollButton"
          type="button"
          class="agent-scroll-latest"
          aria-label="跳转到最新输出"
          @click="scrollToLatest(true)"
        >
          查看最新输出
        </button>
        <div
          class="agent-composer"
          :class="{ 'agent-composer-running': running }"
          @paste="handlePaste"
        >
          <div
            v-if="runMode === 'agent' && selectedSkills.length"
            class="agent-selected-skills"
            aria-label="已选 Skills"
          >
            <span v-for="skill in selectedSkills" :key="skill.id" class="agent-selected-skill">
              <Puzzle :size="12" />
              <span>{{ skill.name }}</span>
              <button
                type="button"
                :aria-label="`移除 Skill ${skill.name}`"
                :disabled="running"
                @click="removeSelectedSkill(skill.id)"
              >
                <X :size="11" />
              </button>
            </span>
          </div>
          <div v-if="imageAttachments.length" class="agent-image-previews" aria-label="待发送图片">
            <div
              v-for="(attachment, index) in imageAttachments"
              :key="`${attachment.name}-${index}`"
              class="agent-image-preview"
            >
              <NImage
                :src="imageAttachmentSrc(attachment)"
                :alt="attachment.name || '待发送图片'"
                object-fit="cover"
              />
              <button
                type="button"
                :aria-label="`移除图片 ${attachment.name || index + 1}`"
                :disabled="running"
                @click="removeImage(index)"
              >
                <X :size="12" />
              </button>
            </div>
          </div>
          <NMention
            v-model:value="input"
            type="textarea"
            :options="runMode === 'agent' ? skillMentionOptions : []"
            :filter="filterSkillMention"
            :render-label="renderSkillMentionLabel"
            :autosize="{ minRows: 2, maxRows: 7 }"
            :disabled="!sshStore.connectionId"
            :loading="runMode === 'agent' && agentStore.loadingSkills"
            :placeholder="
              runMode === 'agent'
                ? '发送消息或创建任务，/ 调用指令，@ 选择 Skill'
                : '发送消息，/ 调用指令'
            "
            class="agent-composer-input"
            @select="selectSkillMention"
            @keydown="handleComposerKeydown"
          >
            <template #empty>
              <div class="agent-skill-mention-empty">当前主机没有可用 Skill</div>
            </template>
          </NMention>
          <div class="agent-composer-footer">
            <div class="agent-composer-actions">
              <input
                ref="imageInput"
                class="agent-image-input"
                type="file"
                accept="image/png,image/jpeg,image/webp,image/gif"
                multiple
                tabindex="-1"
                @change="selectImages"
              />
              <NPopover
                v-model:show="addMenuOpen"
                trigger="click"
                placement="top-start"
                :show-arrow="false"
                :disabled="running"
              >
                <template #trigger>
                  <button
                    type="button"
                    class="agent-compose-add"
                    :disabled="running"
                    :aria-expanded="addMenuOpen"
                    aria-label="添加附件或调用指令"
                    title="添加附件或调用指令"
                  >
                    <Plus :size="16" />
                  </button>
                </template>
                <div class="agent-command-menu">
                  <div class="agent-command-group">添加</div>
                  <button
                    type="button"
                    class="agent-command-item"
                    :disabled="imageAttachments.length >= MAX_IMAGE_ATTACHMENTS"
                    @click="pickComposerImages"
                  >
                    <ImagePlus :size="15" class="agent-command-icon" />
                    <span class="agent-command-label">图片<em>image</em></span>
                    <span class="agent-command-hint">
                      最多 {{ MAX_IMAGE_ATTACHMENTS }} 张，可直接粘贴
                    </span>
                  </button>
                  <div class="agent-command-group">指令</div>
                  <button
                    type="button"
                    class="agent-command-item"
                    :class="{ 'agent-command-item-active': runMode === 'chat' }"
                    :aria-pressed="runMode === 'chat'"
                    :disabled="running || !sshStore.connectionId"
                    @click="selectAiModeFromMenu('chat')"
                  >
                    <MessageCircle :size="15" class="agent-command-icon" />
                    <span class="agent-command-label">对话<em>chat</em></span>
                    <span class="agent-command-hint">不访问主机、不调用工具</span>
                    <Check v-if="runMode === 'chat'" :size="14" class="agent-command-check" />
                  </button>
                  <button
                    type="button"
                    class="agent-command-item"
                    :class="{ 'agent-command-item-active': runMode === 'agent' }"
                    :aria-pressed="runMode === 'agent'"
                    :disabled="running || !sshStore.connectionId"
                    @click="selectAiModeFromMenu('agent')"
                  >
                    <Bot :size="15" class="agent-command-icon" />
                    <span class="agent-command-label">Agent<em>agent</em></span>
                    <span class="agent-command-hint">可使用主机工具、Skills 和 MCP</span>
                    <Check v-if="runMode === 'agent'" :size="14" class="agent-command-check" />
                  </button>
                  <button
                    type="button"
                    class="agent-command-item"
                    :disabled="running"
                    @click="openComposerSettings('tools')"
                  >
                    <Wrench :size="15" class="agent-command-icon" />
                    <span class="agent-command-label">工具<em>tools</em></span>
                    <span class="agent-command-hint">查看可用工具</span>
                  </button>
                  <button
                    type="button"
                    class="agent-command-item"
                    :disabled="running"
                    @click="openComposerSettings('mcp')"
                  >
                    <PlugZap :size="15" class="agent-command-icon" />
                    <span class="agent-command-label">MCP<em>mcp</em></span>
                    <span class="agent-command-hint">
                      已启用 {{ enabledMcpServers.length }} 个服务器
                    </span>
                  </button>
                </div>
              </NPopover>
              <NPopover
                v-model:show="permissionMenuOpen"
                trigger="click"
                placement="top-start"
                :show-arrow="false"
                :disabled="running || !sshStore.connectionId"
              >
                <template #trigger>
                  <button
                    type="button"
                    class="agent-permission-trigger"
                    :class="{ 'agent-permission-auto': autoRun }"
                    :disabled="running || !sshStore.connectionId"
                    :aria-expanded="permissionMenuOpen"
                    aria-label="选择运行权限"
                  >
                    <ShieldCheck v-if="autoRun" :size="13" />
                    <Hand v-else :size="13" />
                    <span>{{ autoRun ? '完全权限' : '按需审批' }}</span>
                    <ChevronDown :size="11" />
                  </button>
                </template>
                <div class="agent-mode-menu">
                  <div class="agent-mode-heading">运行权限</div>
                  <button
                    v-for="mode in [false, true]"
                    :key="String(mode)"
                    type="button"
                    class="agent-mode-option"
                    :class="{ 'agent-mode-auto': mode }"
                    :aria-pressed="autoRun === mode"
                    :disabled="running || !sshStore.connectionId"
                    @click="selectRunMode(mode)"
                  >
                    <ShieldCheck v-if="mode" :size="16" />
                    <Hand v-else :size="16" />
                    <span class="agent-mode-copy">
                      <strong>{{ mode ? '完全权限' : '按需审批' }}</strong>
                      <span>{{
                        mode ? '自动批准所有受保护的工具调用' : '受保护的工具调用前请求批准'
                      }}</span>
                    </span>
                    <Check
                      :size="16"
                      :style="{ visibility: autoRun === mode ? 'visible' : 'hidden' }"
                    />
                  </button>
                </div>
              </NPopover>
              <AiAgentSkillPicker
                v-if="runMode === 'agent'"
                :connection-id="sshStore.connectionId"
                :disabled="running"
                @manage="openSettings('skills')"
              />
            </div>
            <div class="agent-composer-meta">
              <AiAgentModelPicker
                v-model:show="modelPickerOpen"
                :model-name="activeModelName"
                :provider="settings?.provider ?? ''"
                :groups="modelGroups"
                :active-provider="settings?.provider"
                :active-model="settings?.model"
                :levels="agentStore.supportedThinkingLevels"
                :thinking="agentStore.thinkingLevel"
                :switching="switchingModel"
                :disabled="running || modelOptions.length === 0"
                @select="selectModel"
                @update:thinking="agentStore.setThinkingLevel"
              />
              <button
                v-if="running"
                type="button"
                class="agent-send-button agent-stop-button"
                aria-label="停止执行"
                title="停止执行（Esc）"
                @click="stop"
              >
                <Square :size="13" fill="currentColor" />
              </button>
              <button
                v-else
                type="button"
                class="agent-send-button"
                :disabled="!canSend"
                aria-label="发送"
                @click="send"
              >
                <ArrowUp :size="16" />
              </button>
            </div>
          </div>
        </div>
      </footer>
    </main>

    <button
      v-if="sidebarOpen"
      type="button"
      class="agent-mobile-close"
      aria-label="关闭侧边栏"
      @click="sidebarOpen = false"
    >
      <X :size="17" />
    </button>
  </div>
</template>

<style scoped>
.ai-agent-root {
  --agent-bg: transparent;
  --agent-sidebar-bg: transparent;
  --agent-elevated: #ffffff;
  --agent-tool-bg: rgba(241, 245, 249, 0.75);
  --agent-code-bg: #f8fafc;
  --agent-code-toolbar-bg: rgba(37, 99, 235, 0.08);
  --agent-code-toolbar-text: #1d4ed8;
  --agent-code-text: #1e293b;
  --agent-code-keyword: #cf222e;
  --agent-code-string: #0a3069;
  --agent-code-value: #0550ae;
  --agent-code-title: #8250df;
  --agent-code-builtin: #953800;
  --agent-code-tag: #116329;
  --agent-text: #182233;
  --agent-muted: #64748b;
  --agent-border: rgba(100, 116, 139, 0.18);
  --agent-hover: rgba(100, 116, 139, 0.09);
  --agent-active: rgba(100, 116, 139, 0.16);
  position: relative;
  display: flex;
  width: 100%;
  height: 100%;
  min-height: 0;
  overflow: hidden;
  color: var(--agent-text);
  background: var(--agent-bg);
  container-type: inline-size;
}

.ai-agent-dark {
  --agent-bg: transparent;
  --agent-sidebar-bg: transparent;
  --agent-elevated: #1b212a;
  --agent-tool-bg: rgba(30, 37, 47, 0.82);
  --agent-code-bg: #111827;
  --agent-code-toolbar-bg: rgba(96, 165, 250, 0.14);
  --agent-code-toolbar-text: #93c5fd;
  --agent-code-text: #e2e8f0;
  --agent-code-keyword: #ff7b72;
  --agent-code-string: #a5d6ff;
  --agent-code-value: #79c0ff;
  --agent-code-title: #d2a8ff;
  --agent-code-builtin: #ffa657;
  --agent-code-tag: #7ee787;
  --agent-text: #e6eaf0;
  --agent-muted: #8b96a8;
  --agent-border: rgba(148, 163, 184, 0.14);
  --agent-hover: rgba(148, 163, 184, 0.09);
  --agent-active: rgba(148, 163, 184, 0.16);
}

.agent-sidebar {
  position: relative;
  z-index: 20;
  display: flex;
  width: 0;
  min-width: 0;
  height: 100%;
  flex-direction: column;
  overflow: hidden;
  border-right: 1px solid transparent;
  background: var(--agent-sidebar-bg);
  transition:
    width 180ms ease,
    min-width 180ms ease,
    border-color 180ms ease;
}

.ai-agent-sidebar-open .agent-sidebar {
  width: var(--agent-sidebar-width);
  min-width: var(--agent-sidebar-width);
  border-color: var(--agent-border);
}

.ai-agent-sidebar-resizing .agent-sidebar {
  transition: none;
}

.agent-sidebar-resizer {
  position: absolute;
  z-index: 21;
  top: 0;
  bottom: 0;
  width: 10px;
  border: 0;
  background: transparent;
  cursor: col-resize;
  touch-action: none;
  transform: translateX(-5px);
  transition: left 180ms ease;
}

.ai-agent-sidebar-resizing .agent-sidebar-resizer {
  transition: none;
}

.agent-sidebar-resizer::after {
  position: absolute;
  top: 0;
  bottom: 0;
  left: 50%;
  width: 2px;
  border-radius: 999px;
  background: var(--app-primary-color);
  content: '';
  opacity: 0;
  transform: translateX(-50%);
  transition: opacity 150ms ease;
}

.agent-sidebar-resizer:hover::after,
.agent-sidebar-resizer:focus-visible::after,
.agent-sidebar-resizer-active::after {
  opacity: 0.55;
}

.agent-sidebar-resizer:focus-visible {
  outline: none;
}

.agent-sidebar-title {
  display: flex;
  height: 58px;
  flex: 0 0 auto;
  align-items: center;
  justify-content: space-between;
  padding: 0 12px 0 15px;
}

.agent-icon-button,
.agent-history-edit,
.agent-history-delete,
.agent-mobile-close {
  display: grid;
  width: 32px;
  height: 32px;
  flex: 0 0 auto;
  place-items: center;
  border: 0;
  border-radius: var(--app-radius-control);
  color: inherit;
  background: transparent;
  cursor: pointer;
}

.agent-icon-button:hover,
.agent-history-edit:hover,
.agent-history-delete:hover,
.agent-mobile-close:hover {
  background: var(--agent-hover);
}

.agent-history-new:disabled,
.agent-history-open:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.agent-search {
  display: flex;
  height: 31px;
  flex: 0 0 auto;
  align-items: center;
  gap: 7px;
  margin: 0 10px 8px;
  padding: 0 9px;
  border-radius: var(--app-radius-control);
  color: var(--agent-muted);
  background: var(--agent-hover);
}

.agent-search input {
  width: 100%;
  min-width: 0;
  border: 0;
  outline: 0;
  color: var(--agent-text);
  background: transparent;
  font-size: 11px;
}

.agent-history-header {
  display: flex;
  height: 32px;
  flex: 0 0 auto;
  align-items: center;
  justify-content: space-between;
  margin: 6px 10px 2px 16px;
  color: var(--agent-muted);
  font-size: 13px;
}

.agent-history-new {
  display: grid;
  width: 28px;
  height: 28px;
  place-items: center;
  border: 0;
  border-radius: var(--app-radius-control);
  color: inherit;
  background: transparent;
  cursor: pointer;
}

.agent-history-new:hover:not(:disabled) {
  color: var(--agent-text);
  background: var(--agent-hover);
}

.agent-history {
  min-height: 0;
  flex: 1;
  overflow: auto;
  padding: 0 8px 12px 10px;
}

.agent-history-group h2 {
  margin: 12px 8px 4px;
  color: var(--agent-muted);
  font-size: 11px;
  font-weight: 500;
}

.agent-history-group:first-child h2 {
  margin-top: 4px;
}

.agent-history-row {
  display: flex;
  min-width: 0;
  align-items: center;
  margin-bottom: 2px;
  border-radius: 12px;
}

.agent-history-row:hover {
  background: var(--agent-hover);
}

.agent-history-row-active,
.agent-history-row-active:hover {
  background: var(--agent-active);
}

.agent-history-open {
  min-width: 0;
  height: 40px;
  flex: 1;
  overflow: hidden;
  padding: 0 12px;
  border: 0;
  color: inherit;
  background: transparent;
  text-align: left;
  font-size: 13px;
  cursor: pointer;
}

.agent-history-open span {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.agent-history-title-input {
  width: 0;
  min-width: 0;
  height: 28px;
  flex: 1;
  margin: 6px 4px 6px 9px;
  padding: 0 6px;
  border: 1px solid var(--app-primary-border);
  border-radius: var(--app-radius-control);
  outline: 0;
  color: var(--agent-text);
  background: var(--agent-elevated);
  font-size: 13px;
}

.agent-history-edit,
.agent-history-delete {
  width: 28px;
  height: 28px;
  opacity: 0;
}

.agent-history-delete {
  margin-right: 2px;
}

.agent-history-row:hover .agent-history-edit,
.agent-history-row:hover .agent-history-delete,
.agent-history-edit:focus-visible,
.agent-history-delete:focus-visible {
  opacity: 0.62;
}

.agent-sidebar-state {
  padding: 28px 10px;
  color: var(--agent-muted);
  text-align: center;
  font-size: 11px;
}

.agent-main {
  --agent-content-width: 920px;
  --agent-content-gutter: 18px;
  display: flex;
  min-width: 0;
  min-height: 0;
  flex: 1;
  flex-direction: column;
}

.agent-header {
  display: flex;
  height: 58px;
  flex: 0 0 auto;
  align-items: center;
  gap: 10px;
  padding: 0 15px;
  border-bottom: 1px solid var(--agent-border);
  background: color-mix(in srgb, var(--agent-bg) 90%, transparent);
}

.agent-messages {
  min-height: 0;
  flex: 1;
  overflow: auto;
}

.agent-empty-state {
  display: flex;
  width: min(540px, calc(100% - 36px));
  min-height: 100%;
  margin: auto;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 40px 0 80px;
  text-align: center;
}

.agent-empty-mark {
  display: grid;
  width: 52px;
  height: 52px;
  place-items: center;
  border: 1px solid var(--agent-border);
  border-radius: var(--app-radius-surface);
  color: var(--app-primary-color);
  background: var(--app-primary-soft);
  box-shadow: 0 12px 40px rgba(var(--app-primary-rgb), 0.12);
}

.agent-empty-state h1 {
  margin: 21px 0 7px;
  font-size: clamp(22px, 3vw, 30px);
  font-weight: 560;
  letter-spacing: 0;
}

.agent-loading {
  display: flex;
  height: 100%;
  align-items: center;
  justify-content: center;
  gap: 10px;
  color: var(--agent-muted);
  font-size: 12px;
}

.agent-transcript {
  width: min(var(--agent-content-width), calc(100% - 2 * var(--agent-content-gutter)));
  margin: 0 auto;
  padding: 28px 0 36px;
}

.agent-run-phase {
  display: flex;
  align-items: center;
  gap: 7px;
  margin: 0 0 8px;
  color: var(--agent-muted);
  font-size: 11px;
}

.agent-run-phase-spinner {
  flex: 0 0 auto;
  color: var(--app-primary-color);
  animation: agent-spin 1.1s linear infinite;
}

@keyframes agent-spin {
  to {
    transform: rotate(360deg);
  }
}

.agent-message {
  margin: 0 0 25px;
  user-select: text;
}

.agent-message-user {
  width: 100%;
  margin-left: 0;
}

.agent-message-user-wrap {
  display: flex;
  flex-direction: column;
  width: fit-content;
  max-width: min(82%, 620px);
  margin-left: auto;
}

.agent-message-user-bubble {
  padding: 10px 13px;
  border-radius: var(--app-radius-surface) var(--app-radius-surface) 0 var(--app-radius-surface);
  background: var(--app-primary-soft);
}

.agent-message-role {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-bottom: 8px;
  color: var(--agent-muted);
  font-size: 11px;
  font-weight: 600;
  text-transform: capitalize;
}

.agent-message-content {
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  font-size: 13px;
  line-height: 1.78;
}

.agent-message-error {
  padding: 10px 12px;
  border: 1px solid rgba(220, 38, 38, 0.2);
  border-radius: var(--app-radius-item);
  color: #b91c1c;
  background: rgba(254, 226, 226, 0.45);
}

.ai-agent-dark .agent-message-error {
  color: #fca5a5;
  background: rgba(127, 29, 29, 0.2);
}

.agent-message-images {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-bottom: 8px;
}

.agent-message-images :deep(.n-image) {
  width: 68px;
  height: 68px;
  flex: 0 0 auto;
  overflow: hidden;
  border: 1px solid var(--agent-border);
  border-radius: var(--app-radius-item);
  cursor: zoom-in;
}

.agent-message-images :deep(img) {
  width: 100%;
  height: 100%;
}

.agent-thinking {
  display: flex;
  gap: 4px;
  padding: 8px 1px;
}

.agent-thinking span {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: var(--agent-muted);
  animation: agent-thinking 1.2s ease-in-out infinite;
}

.agent-thinking span:nth-child(2) {
  animation-delay: 140ms;
}

.agent-thinking span:nth-child(3) {
  animation-delay: 280ms;
}

.agent-tools {
  margin: 0 0 12px;
}

/* 连续出现的工具卡片归入同一组：只保留首个卡片的 Agent 标题，后续卡片靠间距紧贴上一卡通。 */
.agent-tools-continuation {
  margin-top: -8px;
}

.agent-usage {
  display: flex;
  flex-wrap: wrap;
  gap: 6px 16px;
  margin-top: 18px;
  color: var(--agent-muted);
  text-align: left;
  font-size: 10px;
}

.agent-usage-status {
  font-weight: 600;
}

.agent-usage-success {
  color: #16a34a;
}

.agent-usage-failed,
.agent-usage-expired {
  color: #dc2626;
}

.agent-usage-cancelled {
  color: #d97706;
}

.agent-composer-area {
  z-index: 4;
  flex: 0 0 auto;
  padding: 10px max(var(--agent-content-gutter), calc((100% - var(--agent-content-width)) / 2)) 12px;
  background: linear-gradient(180deg, transparent, var(--agent-bg) 22%);
}

.agent-approvals {
  max-height: min(30vh, 240px);
  margin-bottom: 5px;
  overflow-y: auto;
}

.agent-approval {
  width: 100%;
  margin: 0 0 4px;
  background: var(--agent-elevated);
}

.agent-approval:last-child {
  margin-bottom: 0;
}

.agent-composer {
  overflow: hidden;
  border: 1px solid var(--agent-border);
  border-radius: 20px;
  background: var(--agent-elevated);
  box-shadow: 0 10px 30px rgba(15, 23, 42, 0.08);
  transition:
    border-color 150ms ease,
    box-shadow 150ms ease;
}

.agent-composer:focus-within {
  border-color: var(--app-primary-border);
  box-shadow: 0 10px 34px rgba(var(--app-primary-rgb), 0.1);
}

.agent-composer-running {
  border-color: var(--app-primary-border);
  box-shadow: 0 10px 34px rgba(var(--app-primary-rgb), 0.14);
}

.agent-selected-skills {
  display: flex;
  flex-wrap: wrap;
  gap: 5px;
  padding: 9px 12px 0;
}

.agent-image-previews {
  display: flex;
  gap: 7px;
  overflow-x: auto;
  padding: 10px 12px 0;
}

.agent-image-preview {
  position: relative;
  width: 68px;
  height: 68px;
  flex: 0 0 auto;
}

.agent-image-preview :deep(.n-image) {
  width: 100%;
  height: 100%;
  overflow: hidden;
  border: 1px solid var(--agent-border);
  border-radius: var(--app-radius-item);
  cursor: zoom-in;
}

.agent-image-preview :deep(img) {
  width: 100%;
  height: 100%;
}

.agent-image-preview button {
  position: absolute;
  top: 3px;
  right: 3px;
  display: grid;
  width: 20px;
  height: 20px;
  place-items: center;
  padding: 0;
  border: 0;
  border-radius: 50%;
  color: white;
  background: rgba(15, 23, 42, 0.78);
  cursor: pointer;
}

.agent-selected-skill {
  display: inline-flex;
  max-width: 100%;
  height: 24px;
  align-items: center;
  gap: 5px;
  padding: 0 3px 0 7px;
  border: 1px solid var(--app-primary-border);
  border-radius: var(--app-radius-control);
  color: var(--app-primary-color);
  background: var(--app-primary-soft);
  font-size: 10px;
}

.agent-selected-skill > span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.agent-selected-skill button {
  display: grid;
  width: 18px;
  height: 18px;
  flex: 0 0 auto;
  place-items: center;
  padding: 0;
  border: 0;
  border-radius: var(--app-radius-control);
  color: inherit;
  background: transparent;
  cursor: pointer;
}

.agent-selected-skill button:hover:not(:disabled) {
  background: rgba(var(--app-primary-rgb), 0.13);
}

.agent-selected-skill button:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.agent-composer-input {
  background: transparent !important;
}

.agent-composer-input :deep(.n-input) {
  background: transparent !important;
}

.agent-composer-input :deep(.n-input-wrapper) {
  padding-inline: 0;
}

.agent-composer-input :deep(.n-input__border),
.agent-composer-input :deep(.n-input__state-border) {
  display: none;
}

.agent-composer-input :deep(textarea),
.agent-composer-input :deep(.n-input__placeholder) {
  padding: 14px 16px 6px !important;
  caret-color: var(--app-primary-color);
  font-size: 13px;
  line-height: 1.6;
}

:global(.n-mention-menu) {
  width: min(320px, calc(100vw - 24px));
}

:global(.agent-skill-mention-empty) {
  display: flex;
  min-height: 92px;
  align-items: center;
  justify-content: center;
  padding: 14px;
  color: var(--n-text-color-3, #64748b);
  text-align: center;
  overflow-wrap: anywhere;
  font-size: 11px;
}

:global(.agent-skill-mention-option) {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 8px;
}

:global(.agent-skill-mention-icon) {
  flex: 0 0 auto;
  color: var(--app-primary-color);
}

:global(.agent-skill-mention-name) {
  min-width: 0;
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
  font-weight: 600;
}

:global(.agent-skill-mention-source) {
  max-width: 38%;
  overflow: hidden;
  color: var(--n-option-text-color, #64748b);
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 10px;
  opacity: 0.58;
}

.agent-composer-footer {
  display: flex;
  min-height: 42px;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 2px 8px 8px;
}

.agent-composer-actions {
  display: flex;
  min-width: 0;
  flex: 1;
  align-items: center;
  gap: 8px;
  overflow-x: auto;
  padding: 3px 0;
  white-space: nowrap;
  scrollbar-width: none;
}

.agent-composer-actions::-webkit-scrollbar {
  display: none;
  width: 0;
  height: 0;
}

.agent-composer-actions > * {
  flex-shrink: 0;
}

.agent-compose-add,
.agent-permission-trigger,
.agent-send-button {
  line-height: 1;
}

.agent-image-input {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  opacity: 0;
  pointer-events: none;
}

.agent-compose-add {
  display: grid;
  width: 28px;
  height: 28px;
  flex: 0 0 auto;
  place-items: center;
  padding: 0;
  border: 0;
  border-radius: 50%;
  color: var(--agent-muted);
  background: var(--agent-hover);
  cursor: pointer;
  transition:
    color 150ms ease,
    background 150ms ease;
}

.agent-compose-add:hover:not(:disabled),
.agent-compose-add[aria-expanded='true'] {
  color: var(--app-primary-color);
  background: var(--app-primary-soft);
}

.agent-compose-add:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.agent-command-menu {
  width: min(360px, calc(100vw - 32px));
}

.agent-command-group {
  padding: 2px 8px 4px;
  color: var(--n-text-color-3);
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.04em;
}

.agent-command-group:not(:first-child) {
  margin-top: 4px;
}

.agent-command-item {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 9px;
  padding: 8px;
  border: 0;
  border-radius: var(--app-radius-item);
  color: inherit;
  background: transparent;
  text-align: left;
  cursor: pointer;
}

.agent-command-item:hover:not(:disabled) {
  background: var(--n-color-embedded);
}

.agent-command-item:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.agent-command-icon {
  flex: 0 0 auto;
  color: var(--n-text-color-3);
}

.agent-command-item-active .agent-command-icon {
  color: var(--app-primary-color);
}

.agent-command-label {
  display: inline-flex;
  flex: 0 0 auto;
  align-items: baseline;
  gap: 5px;
  font-size: 12px;
  font-weight: 500;
}

.agent-command-label em {
  color: var(--n-text-color-3);
  font-size: 10px;
  font-style: normal;
  font-weight: 400;
}

.agent-command-hint {
  min-width: 0;
  flex: 1;
  overflow: hidden;
  color: var(--n-text-color-3);
  text-align: right;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 10px;
}

.agent-command-check {
  flex: 0 0 auto;
  color: var(--app-primary-color);
}

.agent-permission-trigger {
  display: inline-flex;
  height: 28px;
  flex: 0 0 auto;
  align-items: center;
  gap: 5px;
  padding: 0 8px;
  border: 0;
  border-radius: var(--app-radius-control);
  color: var(--agent-muted);
  background: transparent;
  font-size: 12px;
  cursor: pointer;
  transition:
    color 150ms ease,
    background 150ms ease;
}

.agent-permission-trigger:hover:not(:disabled),
.agent-permission-trigger[aria-expanded='true'] {
  color: var(--agent-text);
  background: var(--agent-hover);
}

.agent-permission-trigger:disabled,
.agent-mode-option:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.agent-permission-auto,
.agent-permission-auto:hover:not(:disabled) {
  color: #e7823b;
}

.agent-composer-meta {
  display: flex;
  flex: 0 0 auto;
  align-items: center;
  gap: 6px;
}

.agent-mode-menu {
  width: min(320px, calc(100vw - 48px));
}

.agent-mode-heading {
  padding: 2px 8px 8px;
  font-size: 11px;
  opacity: 0.55;
}

.agent-mode-option {
  display: grid;
  width: 100%;
  grid-template-columns: 16px minmax(0, 1fr) 16px;
  align-items: center;
  gap: 10px;
  padding: 10px 8px;
  border: 0;
  border-radius: var(--app-radius-item);
  color: inherit;
  background: transparent;
  text-align: left;
  cursor: pointer;
}

.agent-mode-option:hover:not(:disabled) {
  background: var(--n-color-embedded);
}

.agent-mode-copy {
  display: grid;
  gap: 3px;
  font-size: 11px;
  line-height: 1.5;
}

.agent-mode-copy strong {
  font-size: 13px;
  font-weight: 600;
}

.agent-mode-copy > span {
  opacity: 0.65;
}

.agent-mode-auto {
  color: #e7823b;
}

.agent-permission-trigger:focus-visible,
.agent-mode-option:focus-visible {
  outline: 2px solid var(--app-primary-color);
  outline-offset: 2px;
}

.agent-send-button {
  display: grid;
  width: 32px;
  height: 32px;
  flex: 0 0 auto;
  place-items: center;
  padding: 0;
  border: 0;
  border-radius: 50%;
  color: white;
  background: var(--app-primary-color);
  cursor: pointer;
  transition:
    transform 120ms ease,
    background 150ms ease,
    opacity 150ms ease;
}

.agent-send-button:hover:not(:disabled) {
  transform: translateY(-1px);
}

.agent-send-button:disabled {
  color: var(--agent-muted);
  background: var(--agent-hover);
  cursor: not-allowed;
}

.agent-stop-button {
  color: white;
  background: var(--app-primary-color);
  box-shadow: 0 0 0 3px rgba(var(--app-primary-rgb), 0.16);
}

.agent-stop-button:hover {
  transform: none;
  background: var(--app-primary-color);
}

.agent-error {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin: 0 8px 8px;
  color: #dc2626;
  font-size: 11px;
}

.agent-error-retry {
  display: inline-flex;
  flex: 0 0 auto;
  align-items: center;
  gap: 4px;
  padding: 3px 7px;
  border: 1px solid currentColor;
  border-radius: var(--app-radius-control);
  color: inherit;
  background: transparent;
  cursor: pointer;
}

.agent-scroll-latest {
  display: block;
  margin: 0 auto 7px;
  padding: 4px 9px;
  border: 1px solid var(--app-primary-border);
  border-radius: var(--app-radius-control);
  color: var(--app-primary-color);
  background: var(--app-primary-soft);
  font-size: 10px;
  cursor: pointer;
}

.agent-configure {
  display: block;
  margin: 0 auto 8px;
  padding: 6px 10px;
  border: 0;
  border-radius: var(--app-radius-control);
  color: var(--app-primary-color);
  background: var(--app-primary-soft);
  font-size: 11px;
  cursor: pointer;
}

.agent-sidebar-backdrop,
.agent-mobile-close {
  display: none;
}

@keyframes agent-thinking {
  0%,
  60%,
  100% {
    opacity: 0.32;
    transform: translateY(0);
  }
  30% {
    opacity: 1;
    transform: translateY(-3px);
  }
}

@container (max-width: 759px) {
  .agent-sidebar {
    position: absolute;
    inset: 0 auto 0 0;
    width: min(290px, calc(100% - 42px));
    min-width: min(290px, calc(100% - 42px));
    border-right-color: var(--agent-border);
    box-shadow: 18px 0 50px rgba(2, 6, 23, 0.22);
    transform: translateX(-105%);
    transition: transform 180ms ease;
  }

  .ai-agent-sidebar-open .agent-sidebar {
    width: min(290px, calc(100% - 42px));
    min-width: min(290px, calc(100% - 42px));
    transform: translateX(0);
  }

  .agent-sidebar-backdrop {
    position: absolute;
    inset: 0;
    z-index: 15;
    display: block;
    border: 0;
    background: rgba(2, 6, 23, 0.38);
  }

  .agent-mobile-close {
    position: absolute;
    z-index: 25;
    top: 12px;
    right: 7px;
    display: grid;
    color: white;
    background: rgba(15, 23, 42, 0.66);
  }

  .agent-sidebar-resizer {
    display: none;
  }

  .agent-main {
    --agent-content-gutter: 10px;
  }

  .agent-transcript {
    padding-top: 20px;
  }

  .agent-message-user {
    max-width: 90%;
  }
}

@media (prefers-reduced-motion: reduce) {
  .agent-sidebar,
  .agent-run-phase-spinner,
  .agent-thinking span {
    transition: none;
    animation: none;
  }
}
</style>
