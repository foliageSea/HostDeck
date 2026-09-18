<script setup lang="ts">
import { computed, h, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import type { MentionOption } from 'naive-ui'
import {
  Bot,
  Check,
  ChevronDown,
  Hand,
  ImagePlus,
  ShieldAlert,
  Menu,
  MessageCircle,
  MessageSquarePlus,
  PanelLeftClose,
  Pencil,
  PlugZap,
  Puzzle,
  Search,
  Send,
  Settings,
  Square,
  Trash2,
  Wrench,
  X,
} from '@lucide/vue'
import { aiAgentApi, type AiAgentConversation, type AiAgentImageAttachment } from '@/api/ai-agent'
import { getUiApi } from '@/lib/ui'
import { MAX_SELECTED_SKILLS, useAiAgentStore } from '@/stores/ai-agent'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'
import AiAgentMarkdown from './components/AiAgentMarkdown.vue'
import AiAgentSkillPicker from './components/AiAgentSkillPicker.vue'
import AiAgentSettingsModal from './components/AiAgentSettingsModal.vue'
import AiAgentToolCall from './components/AiAgentToolCall.vue'
import {
  filesToImageAttachments,
  imageAttachmentSrc,
  MAX_IMAGE_ATTACHMENTS,
} from './components/image-attachments'

interface ConversationGroup {
  label: string
  conversations: AiAgentConversation[]
}

const agentStore = useAiAgentStore()
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
  usage,
} = storeToRefs(agentStore)

const rootElement = ref<HTMLElement>()
const compactLayout = ref(false)
const sidebarOpen = ref(true)
const settingsOpen = ref(false)
const modeMenuOpen = ref(false)
const modelMenuOpen = ref(false)
const settingsSection = ref<'mcp' | 'model'>('model')
const query = ref('')
const input = ref('')
const imageInput = ref<HTMLInputElement>()
const imageAttachments = ref<AiAgentImageAttachment[]>([])
const messageScroller = ref<HTMLElement>()
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
    settings.value?.hasApiKey &&
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

const pendingToolCalls = computed(() => toolCalls.value.filter((tool) => tool.approvalPending))
const completedToolCalls = computed(() => toolCalls.value.filter((tool) => !tool.approvalPending))
const enabledMcpServers = computed(() => agentStore.mcpServers.filter((server) => server.enabled))
const modelOptions = computed(() =>
  (settings.value?.models ?? []).map((model) => ({ label: model.name, value: model.id })),
)
const activeModelName = computed(() => {
  const activeModel = settings.value?.models.find((model) => model.id === settings.value?.model)
  return activeModel?.name || settings.value?.model || '选择模型'
})

function openSettings(section: 'mcp' | 'model' = 'model') {
  settingsSection.value = section
  settingsOpen.value = true
}

function selectRunMode(mode: boolean) {
  if (running.value || !sshStore.connectionId) return
  autoRun.value = mode
  modeMenuOpen.value = false
}

function selectAiMode(mode: 'chat' | 'agent') {
  if (!sshStore.connectionId || running.value) return
  agentStore.setRunMode(mode)
}

function closeSidebarOnNarrowScreen() {
  if (compactLayout.value) sidebarOpen.value = false
}

async function loadForConnection(connectionId: string) {
  try {
    await Promise.all([
      agentStore.loadSettings(),
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
  if (!connectionId || loadingConversation.value) return
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

async function switchModel(model: string) {
  if (model === settings.value?.model || switchingModel.value || running.value) return true
  switchingModel.value = true
  try {
    await agentStore.saveSettings({ model })
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

async function selectModel(model: string) {
  if (await switchModel(model)) modelMenuOpen.value = false
}

function handleComposerKeydown(event: KeyboardEvent) {
  if (event.defaultPrevented || event.key !== 'Enter' || event.shiftKey || event.isComposing) return
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

function scrollToLatest() {
  void nextTick(() => {
    if (messageScroller.value) {
      messageScroller.value.scrollTop = messageScroller.value.scrollHeight
    }
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

watch(() => [messages.value.at(-1)?.content, toolCalls.value.length, running.value], scrollToLatest)

onMounted(() => {
  if (typeof ResizeObserver !== 'undefined') {
    resizeObserver = new ResizeObserver(([entry]) => {
      const compact = (entry?.contentRect.width ?? 760) < 760
      if (compact !== compactLayout.value) {
        compactLayout.value = compact
        sidebarOpen.value = !compact
      }
    })
    if (rootElement.value) resizeObserver.observe(rootElement.value)
  }
  window.addEventListener('beforeunload', handleBeforeUnload)
})

onBeforeUnmount(() => {
  resizeObserver?.disconnect()
  window.removeEventListener('beforeunload', handleBeforeUnload)
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
      { 'ai-agent-sidebar-open': sidebarOpen },
    ]"
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

      <button
        type="button"
        class="agent-new-conversation"
        :disabled="!sshStore.connectionId || running"
        @click="newConversation"
      >
        <MessageSquarePlus :size="16" />
        新建对话
      </button>

      <label class="agent-search">
        <Search :size="14" />
        <input v-model="query" type="search" placeholder="搜索对话" aria-label="搜索对话" />
      </label>

      <div class="agent-history app-scrollbar app-scrollbar-compact">
        <div v-if="loadingConversations" class="agent-sidebar-state">正在加载对话…</div>
        <div v-else-if="conversationGroups.length === 0" class="agent-sidebar-state">
          {{ query ? '没有匹配的对话' : '还没有对话' }}
        </div>
        <section v-for="group in conversationGroups" :key="group.label" class="agent-history-group">
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

      <button type="button" class="agent-settings-entry" @click="openSettings()">
        <Settings :size="16" />
        <span class="min-w-0 flex-1 text-left">
          <strong class="block text-[12px] font-medium">模型设置</strong>
          <small class="block truncate text-[10px] opacity-55">{{
            settings?.model || '尚未配置'
          }}</small>
        </span>
      </button>
    </aside>

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
            <span class="truncate">{{ settings?.model || '未配置模型' }}</span>
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

      <div ref="messageScroller" class="agent-messages app-scrollbar">
        <div v-if="loadingConversation" class="agent-loading">
          <NSpin size="small" /> 正在加载对话
        </div>
        <div v-else-if="messages.length === 0 && toolCalls.length === 0" class="agent-empty-state">
          <div class="agent-empty-mark"><Bot :size="27" /></div>
          <h1>{{ runMode === 'agent' ? '我们要维护什么？' : '今天想聊些什么？' }}</h1>
        </div>
        <div v-else class="agent-transcript">
          <article
            v-for="message in messages"
            :key="message.id"
            class="agent-message"
            :class="`agent-message-${message.role}`"
          >
            <div v-if="message.role !== 'user'" class="agent-message-role">
              <Bot v-if="message.role === 'assistant'" :size="14" />
              <Wrench v-else :size="14" />
              {{ message.role === 'assistant' ? 'Agent' : message.role }}
            </div>
            <AiAgentMarkdown
              v-if="message.content && message.role === 'assistant'"
              :content="message.content"
            />
            <div
              v-if="message.role === 'user' && message.attachments?.length"
              class="agent-message-images"
            >
              <NImage
                v-for="(attachment, index) in message.attachments"
                :key="`${message.id}-${index}`"
                :src="imageAttachmentSrc(attachment)"
                :alt="attachment.name || '上传的图片'"
                object-fit="cover"
                lazy
              />
            </div>
            <div
              v-if="message.content && message.role !== 'assistant'"
              class="agent-message-content"
            >
              {{ message.content }}
            </div>
            <div
              v-else-if="message.role === 'assistant' && message.id === streamingMessageId"
              class="agent-thinking"
              aria-label="Agent 正在思考"
            >
              <span /><span /><span />
            </div>
          </article>

          <div v-if="completedToolCalls.length" class="agent-tools">
            <AiAgentToolCall
              v-for="tool in completedToolCalls"
              :key="tool.callId"
              :tool="tool"
              @approve="resolveApproval($event, true)"
              @reject="resolveApproval($event, false)"
            />
          </div>
          <div v-if="usage?.totalTokens != null || durationMs != null" class="agent-usage">
            <span v-if="usage?.totalTokens != null">
              本次使用 {{ usage.totalTokens.toLocaleString() }} tokens
            </span>
            <span v-if="durationMs != null">执行耗时 {{ (durationMs / 1000).toFixed(1) }} 秒</span>
          </div>
        </div>
      </div>

      <footer class="agent-composer-area">
        <div v-if="error" class="agent-error" role="alert">{{ error }}</div>
        <div
          v-if="pendingToolCalls.length"
          class="agent-approvals app-scrollbar app-scrollbar-compact"
          aria-label="权限申请"
        >
          <AiAgentToolCall
            v-for="tool in pendingToolCalls"
            :key="tool.callId"
            :tool="tool"
            class="agent-approval"
            @approve="resolveApproval($event, true)"
            @reject="resolveApproval($event, false)"
          />
        </div>
        <button
          v-if="settings && !settings.hasApiKey"
          type="button"
          class="agent-configure"
          @click="openSettings()"
        >
          配置 API Key 后开始对话
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
            :placeholder="runMode === 'agent' ? '描述任务，输入 @ 选择 Skill' : '输入消息'"
            class="agent-composer-input"
            @select="selectSkillMention"
            @keydown="handleComposerKeydown"
          >
            <template #empty>
              <div class="agent-skill-mention-empty">当前主机没有可用 Skill</div>
            </template>
          </NMention>
          <div class="agent-composer-footer">
            <div class="flex min-w-0 flex-wrap items-center gap-2">
              <input
                ref="imageInput"
                class="agent-image-input"
                type="file"
                accept="image/png,image/jpeg,image/webp,image/gif"
                multiple
                tabindex="-1"
                @change="selectImages"
              />
              <button
                type="button"
                class="agent-attachment-button"
                :disabled="running || imageAttachments.length >= MAX_IMAGE_ATTACHMENTS"
                aria-label="添加图片"
                title="添加图片"
                @click="imageInput?.click()"
              >
                <ImagePlus :size="14" />
              </button>
              <div class="agent-ai-mode" role="group" aria-label="对话模式">
                <button
                  type="button"
                  :class="{ 'agent-ai-mode-active': runMode === 'chat' }"
                  :aria-pressed="runMode === 'chat'"
                  :disabled="running || !sshStore.connectionId"
                  title="Chat 模式不会访问主机或调用工具"
                  @click="selectAiMode('chat')"
                >
                  <MessageCircle :size="12" />
                  Chat
                </button>
                <button
                  type="button"
                  :class="{ 'agent-ai-mode-active': runMode === 'agent' }"
                  :aria-pressed="runMode === 'agent'"
                  :disabled="running || !sshStore.connectionId"
                  title="Agent 模式可使用主机工具、Skills 和 MCP"
                  @click="selectAiMode('agent')"
                >
                  <Bot :size="12" />
                  Agent
                </button>
              </div>
              <NPopover
                v-model:show="modelMenuOpen"
                trigger="click"
                placement="top-start"
                :show-arrow="false"
                :disabled="running || !settings?.hasApiKey || modelOptions.length === 0"
              >
                <template #trigger>
                  <button
                    type="button"
                    class="agent-mode-trigger agent-model-trigger"
                    :disabled="running || !settings?.hasApiKey || modelOptions.length === 0"
                    :aria-expanded="modelMenuOpen"
                    aria-label="选择模型"
                  >
                    <Bot :size="13" />
                    <span>{{ activeModelName }}</span>
                    <ChevronDown :size="11" />
                  </button>
                </template>
                <div class="agent-mode-menu agent-model-menu">
                  <div class="agent-mode-heading">选择模型</div>
                  <button
                    v-for="model in modelOptions"
                    :key="model.value"
                    type="button"
                    class="agent-mode-option"
                    :aria-pressed="settings?.model === model.value"
                    :disabled="switchingModel || running"
                    @click="selectModel(model.value)"
                  >
                    <Bot :size="16" />
                    <span class="agent-mode-copy">
                      <strong>{{ model.label }}</strong>
                      <span>{{ model.value }}</span>
                    </span>
                    <Check
                      :size="16"
                      :style="{
                        visibility: settings?.model === model.value ? 'visible' : 'hidden',
                      }"
                    />
                  </button>
                </div>
              </NPopover>
              <AiAgentSkillPicker
                v-if="runMode === 'agent'"
                :connection-id="sshStore.connectionId"
                :disabled="running"
              />
              <button
                v-if="runMode === 'agent'"
                type="button"
                class="agent-mcp-entry"
                :disabled="running"
                aria-label="MCP 服务器设置"
                @click="openSettings('mcp')"
              >
                <PlugZap :size="12" />
                MCP {{ enabledMcpServers.length }}
              </button>
              <NPopover
                v-if="runMode === 'agent'"
                v-model:show="modeMenuOpen"
                trigger="click"
                placement="top-start"
                :show-arrow="false"
                :disabled="running || !sshStore.connectionId"
              >
                <template #trigger>
                  <button
                    type="button"
                    class="agent-mode-trigger"
                    :class="{ 'agent-mode-auto': autoRun }"
                    :disabled="running || !sshStore.connectionId"
                    :aria-expanded="modeMenuOpen"
                    aria-label="选择运行模式"
                  >
                    <ShieldAlert v-if="autoRun" :size="13" />
                    <Hand v-else :size="13" />
                    <span>{{ autoRun ? '自动运行' : '按需审批' }}</span>
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
                    <ShieldAlert v-if="mode" :size="16" />
                    <Hand v-else :size="16" />
                    <span class="agent-mode-copy">
                      <strong>{{ mode ? '自动运行' : '按需审批' }}</strong>
                      <span>{{
                        mode
                          ? '自动批准命令执行、文件读写及 MCP 调用'
                          : '命令执行、文件读写及 MCP 调用前请求批准'
                      }}</span>
                    </span>
                    <Check
                      :size="16"
                      :style="{ visibility: autoRun === mode ? 'visible' : 'hidden' }"
                    />
                  </button>
                </div>
              </NPopover>
            </div>
            <button
              v-if="running"
              type="button"
              class="agent-send-button agent-stop-button"
              aria-label="停止"
              @click="stop"
            >
              <Square :size="14" fill="currentColor" />
            </button>
            <button
              v-else
              type="button"
              class="agent-send-button"
              :disabled="!canSend"
              aria-label="发送"
              @click="send"
            >
              <Send :size="15" />
            </button>
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

    <AiAgentSettingsModal v-model:show="settingsOpen" :initial-tab="settingsSection" />
  </div>
</template>

<style scoped>
.ai-agent-root {
  --agent-bg: #f8fafc;
  --agent-sidebar-bg: #f1f5f9;
  --agent-elevated: #ffffff;
  --agent-tool-bg: rgba(241, 245, 249, 0.75);
  --agent-code-bg: #e8edf3;
  --agent-text: #182233;
  --agent-muted: #64748b;
  --agent-border: rgba(100, 116, 139, 0.18);
  --agent-hover: rgba(100, 116, 139, 0.09);
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
  --agent-bg: #11151b;
  --agent-sidebar-bg: #171c23;
  --agent-elevated: #1b212a;
  --agent-tool-bg: rgba(30, 37, 47, 0.82);
  --agent-code-bg: #10141a;
  --agent-text: #e6eaf0;
  --agent-muted: #8b96a8;
  --agent-border: rgba(148, 163, 184, 0.14);
  --agent-hover: rgba(148, 163, 184, 0.09);
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
  width: 240px;
  min-width: 240px;
  border-color: var(--agent-border);
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

.agent-new-conversation {
  display: flex;
  height: 36px;
  flex: 0 0 auto;
  align-items: center;
  gap: 9px;
  margin: 2px 10px 10px;
  padding: 0 11px;
  border: 1px solid var(--agent-border);
  border-radius: var(--app-radius-control);
  color: inherit;
  background: var(--agent-elevated);
  font-size: 12px;
  cursor: pointer;
}

.agent-new-conversation:hover:not(:disabled) {
  border-color: var(--app-primary-border);
  background: var(--app-primary-soft);
}

.agent-new-conversation:disabled,
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

.agent-history {
  min-height: 0;
  flex: 1;
  overflow: auto;
  padding: 0 2px 12px 7px;
}

.agent-history-group h2 {
  margin: 13px 8px 5px;
  color: var(--agent-muted);
  font-size: 10px;
  font-weight: 500;
}

.agent-history-row {
  display: flex;
  min-width: 0;
  align-items: center;
  border: 1px solid transparent;
  border-radius: var(--app-radius-item);
}

.agent-history-row:hover,
.agent-history-row-active {
  background: var(--agent-hover);
}

.agent-history-row-active {
  border-color: var(--app-primary-border);
  background: var(--app-primary-soft);
}

.agent-history-open {
  min-width: 0;
  height: 32px;
  flex: 1;
  overflow: hidden;
  padding: 0 9px;
  border: 0;
  color: inherit;
  background: transparent;
  text-align: left;
  font-size: 11px;
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
  height: 26px;
  flex: 1;
  margin: 3px 4px 3px 7px;
  padding: 0 5px;
  border: 1px solid var(--app-primary-border);
  border-radius: var(--app-radius-control);
  outline: 0;
  color: var(--agent-text);
  background: var(--agent-elevated);
  font-size: 11px;
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

.agent-settings-entry {
  display: flex;
  min-height: 52px;
  flex: 0 0 auto;
  align-items: center;
  gap: 10px;
  margin: 7px;
  padding: 7px 10px;
  border: 1px solid var(--agent-border);
  border-radius: var(--app-radius-item);
  color: inherit;
  background: var(--agent-elevated);
  cursor: pointer;
}

.agent-settings-entry:hover {
  border-color: var(--app-primary-border);
  background: var(--app-primary-soft);
}

.agent-main {
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
  width: min(760px, calc(100% - 48px));
  margin: 0 auto;
  padding: 28px 0 36px;
}

.agent-message {
  margin: 0 0 25px;
  user-select: text;
}

.agent-message-user {
  width: fit-content;
  max-width: min(82%, 620px);
  margin-left: auto;
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
  margin-top: -12px;
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

.agent-composer-area {
  z-index: 4;
  flex: 0 0 auto;
  padding: 10px max(18px, calc((100% - 760px) / 2)) 12px;
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
  border-radius: var(--app-radius-card);
  background: var(--agent-elevated);
  box-shadow: 0 12px 38px rgba(15, 23, 42, 0.1);
  transition:
    border-color 150ms ease,
    box-shadow 150ms ease;
}

.agent-composer-running {
  border-color: var(--app-primary-border);
  box-shadow: 0 12px 42px rgba(var(--app-primary-rgb), 0.12);
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
  padding: 13px 14px 4px !important;
  caret-color: var(--app-primary-color);
  font-size: 12px;
  line-height: 1.65;
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
  min-height: 41px;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  padding: 4px 7px 7px 12px;
}

.agent-image-input {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  opacity: 0;
  pointer-events: none;
}

.agent-attachment-button {
  display: grid;
  width: 25px;
  height: 25px;
  flex: 0 0 auto;
  place-items: center;
  padding: 0;
  border: 0;
  border-radius: var(--app-radius-control);
  color: var(--agent-muted);
  background: var(--agent-hover);
  cursor: pointer;
}

.agent-attachment-button:hover:not(:disabled) {
  color: var(--app-primary-color);
  background: var(--app-primary-soft);
}

.agent-attachment-button:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.agent-ai-mode {
  display: inline-grid;
  height: 25px;
  flex: 0 0 auto;
  grid-template-columns: repeat(2, auto);
  padding: 2px;
  border: 1px solid var(--agent-border);
  border-radius: var(--app-radius-control);
  background: var(--agent-hover);
}

.agent-ai-mode button {
  display: inline-flex;
  min-width: 54px;
  align-items: center;
  justify-content: center;
  gap: 4px;
  padding: 0 6px;
  border: 0;
  border-radius: calc(var(--app-radius-control) - 2px);
  color: var(--agent-muted);
  background: transparent;
  font-size: 9px;
  cursor: pointer;
}

.agent-ai-mode button.agent-ai-mode-active {
  color: var(--agent-text);
  background: var(--agent-elevated);
  box-shadow: 0 1px 3px rgba(15, 23, 42, 0.12);
}

.agent-ai-mode button:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.agent-ai-mode button:focus-visible {
  outline: 2px solid var(--app-primary-color);
  outline-offset: 1px;
}

.agent-model-trigger {
  max-width: min(180px, 42vw);
}

.agent-model-trigger > span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.agent-model-menu {
  width: min(360px, calc(100vw - 48px));
}

.agent-mcp-entry {
  display: inline-flex;
  height: 23px;
  align-items: center;
  gap: 4px;
  padding: 0 7px;
  border: 0;
  border-radius: var(--app-radius-control);
  color: var(--agent-muted);
  background: var(--agent-hover);
  font-size: 9px;
  cursor: pointer;
}

.agent-mcp-entry:hover:not(:disabled) {
  color: var(--app-primary-color);
  background: var(--app-primary-soft);
}

.agent-mode-trigger {
  display: inline-flex;
  height: 25px;
  flex-shrink: 0;
  align-items: center;
  gap: 5px;
  padding: 0 7px;
  border: 0;
  border-radius: var(--app-radius-control);
  color: var(--agent-muted);
  background: var(--agent-hover);
  font-size: 10px;
  cursor: pointer;
}

.agent-mode-trigger:hover:not(:disabled) {
  background: var(--app-primary-soft);
}

.agent-mode-trigger:disabled,
.agent-mode-option:disabled {
  opacity: 0.45;
  cursor: not-allowed;
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
  border-radius: 6px;
  color: inherit;
  background: transparent;
  text-align: left;
  cursor: pointer;
}

.agent-mode-option:hover:not(:disabled) {
  background: var(--app-primary-soft);
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

.agent-mode-trigger:focus-visible,
.agent-mode-option:focus-visible {
  outline: 2px solid var(--app-primary-color);
  outline-offset: 2px;
}

.agent-send-button {
  display: grid;
  width: 31px;
  height: 31px;
  flex: 0 0 auto;
  place-items: center;
  border: 0;
  border-radius: var(--app-radius-control);
  color: white;
  background: var(--app-primary-color);
  cursor: pointer;
}

.agent-send-button:disabled {
  color: var(--agent-muted);
  background: var(--agent-hover);
  cursor: not-allowed;
}

.agent-stop-button {
  color: var(--agent-text);
  background: var(--agent-hover);
}

.agent-error {
  margin: 0 8px 8px;
  color: #dc2626;
  font-size: 11px;
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

  .agent-transcript {
    width: calc(100% - 30px);
    padding-top: 20px;
  }

  .agent-message-user {
    max-width: 90%;
  }

  .agent-composer-area {
    padding-right: 10px;
    padding-left: 10px;
  }
}

@media (prefers-reduced-motion: reduce) {
  .agent-sidebar,
  .agent-thinking span {
    transition: none;
    animation: none;
  }
}
</style>
