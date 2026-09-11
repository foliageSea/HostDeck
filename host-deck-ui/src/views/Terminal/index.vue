<script setup lang="ts">
import { ref } from 'vue'
import { FolderOpen, Help, Settings, Terminal } from '@vicons/carbon'
import '@xterm/xterm/css/xterm.css'
import TerminalCompletionPopover from './components/TerminalCompletionPopover.vue'
import TerminalSettingsModal from './components/TerminalSettingsModal.vue'
import TerminalSnippetsModal from './components/TerminalSnippetsModal.vue'
import { useTerminalSession } from './hooks/useTerminalSession'
import { useSettingsStore } from '@/stores/settings'
import { useDesktopStore } from '@/stores/desktop'
import { useSshStore } from '@/stores/ssh'
import { getUiApi } from '@/lib/ui'

const props = defineProps<{
  windowId?: string
  connectionId?: string
  host?: string
  username?: string
  sessionId?: string
  cwd?: string
  startupCommand?: string
  openIframeAfterMs?: number
  openIframeTitle?: string
  openIframeUrl?: string
  shutdownCommand?: string
  closeSessionOnUnmount?: boolean
  closeConnectionOnUnmount?: boolean
}>()

const settingsStore = useSettingsStore()
const desktopStore = useDesktopStore()
const sshStore = useSshStore()
const showSettings = ref(false)
const showSnippets = ref(false)
const showCopyButton = ref(false)
const openingCurrentDirectory = ref(false)
const selectedText = ref('')
const copyButtonStyle = ref({ left: '0px', top: '0px' })
const { completion, requestCurrentDirectory, terminal, terminalContainer } =
  useTerminalSession(props)

void terminalContainer

function openCopyButton(event: MouseEvent) {
  if (!terminal.value?.hasSelection()) {
    showCopyButton.value = false
    return
  }

  const selection = terminal.value.getSelection()
  if (!selection) {
    showCopyButton.value = false
    return
  }

  selectedText.value = selection
  copyButtonStyle.value = {
    left: `${Math.min(Math.max(event.clientX, 56), window.innerWidth - 56)}px`,
    top: `${Math.max(event.clientY, 40)}px`,
  }
  showCopyButton.value = true
}

function handleWheel(event: WheelEvent) {
  if (!event.ctrlKey || event.deltaY === 0) {
    return
  }

  event.preventDefault()
  settingsStore.setTerminalFontSize(settingsStore.terminalFontSize + (event.deltaY < 0 ? 1 : -1))
}

async function copySelection() {
  if (!selectedText.value) {
    return
  }

  try {
    await navigator.clipboard.writeText(selectedText.value)
    getUiApi().message.success('已复制终端选中文本。')
    terminal.value?.clearSelection()
    showCopyButton.value = false
  } catch (error) {
    console.error('Failed to copy terminal text', error)
    getUiApi().message.error('复制失败。')
  }
}

function insertSnippet(command: string) {
  terminal.value?.paste(command)
  terminal.value?.focus()
}

function setActiveCompletion(index: number) {
  completion.activeIndex.value = index
}

function openSnippets() {
  completion.close()
  showSnippets.value = true
}

function openSettings() {
  completion.close()
  showSettings.value = true
}

async function openCurrentDirectory() {
  if (openingCurrentDirectory.value) {
    return
  }

  openingCurrentDirectory.value = true
  try {
    const path = await requestCurrentDirectory()
    const connectionId = props.connectionId ?? sshStore.connectionId
    if (!connectionId) {
      throw new Error('当前没有可用的 SSH 连接。')
    }

    desktopStore.openWindow(
      'files',
      {
        connectionId,
        host: props.host ?? sshStore.host,
        path,
        title: `文件管理 · ${path}`,
        username: props.username ?? sshStore.username,
      },
      { parentId: props.windowId },
    )
  } catch (error) {
    const message = error instanceof Error ? error.message : '无法获取终端当前目录。'
    getUiApi().message.error(message)
  } finally {
    openingCurrentDirectory.value = false
    terminal.value?.focus()
  }
}
</script>

<template>
  <div
    class="relative flex h-full flex-col"
    :class="[
      settingsStore.isDark
        ? 'bg-[radial-gradient(circle_at_top,rgba(15,23,42,0.55),#020617_72%)]'
        : 'bg-[radial-gradient(circle_at_top,rgba(255,255,255,0.82),#f8fafc_72%)]',
    ]"
    @mousedown="showCopyButton = false"
    @mouseup="openCopyButton"
    @wheel="handleWheel"
  >
    <div
      class="app-radius-card terminal-surface min-h-0 flex-1 overflow-hidden border mx-[12px] mb-[8px]"
    >
      <div
        ref="terminalContainer"
        class="terminal-host h-full min-h-0 overflow-hidden rounded-[inherit] px-2"
      />
    </div>

    <div
      class="app-radius-card flex shrink-0 items-center justify-between border px-[12px] py-[8px] mx-[12px] mb-[12px]"
      :class="settingsStore.isDark ? 'bg-[#050816]' : 'bg-[#f8fafc]'"
    >
      <div class="flex items-center gap-[8px]">
        <NTooltip trigger="hover">
          <template #trigger>
            <NButton
              quaternary
              circle
              size="small"
              :loading="openingCurrentDirectory"
              aria-label="在文件管理器中打开当前目录"
              @click="openCurrentDirectory"
            >
              <template #icon>
                <NIcon :size="16">
                  <FolderOpen />
                </NIcon>
              </template>
            </NButton>
          </template>
          在文件管理器中打开当前目录
        </NTooltip>

        <NTooltip trigger="hover">
          <template #trigger>
            <NButton quaternary circle size="small" aria-label="命令片段" @click="openSnippets">
              <template #icon>
                <NIcon :size="16">
                  <Terminal />
                </NIcon>
              </template>
            </NButton>
          </template>
          命令片段
        </NTooltip>
      </div>

      <div class="flex items-center gap-[8px]">
        <NPopover trigger="hover" placement="top-end">
          <template #trigger>
            <NButton quaternary circle size="small" aria-label="终端快捷键">
              <template #icon>
                <NIcon :size="16">
                  <Help />
                </NIcon>
              </template>
            </NButton>
          </template>
          <div
            class="flex flex-col gap-[6px] text-[12px]"
            :class="
              settingsStore.isDark
                ? 'text-[rgba(226,232,240,0.96)]'
                : 'text-[rgba(51,65,85,0.96)]'
            "
          >
            <div>Ctrl + V：粘贴</div>
            <div>Alt + C：复制选中内容</div>
            <div>输入至少 2 个字符：显示命令补全</div>
            <div>补全中使用 ↑↓ 选择，Tab 填入，Enter 执行</div>
          </div>
        </NPopover>

        <NTooltip trigger="hover">
          <template #trigger>
            <NButton quaternary circle size="small" aria-label="终端设置" @click="openSettings">
              <template #icon>
                <NIcon :size="16">
                  <Settings />
                </NIcon>
              </template>
            </NButton>
          </template>
          终端设置
        </NTooltip>
      </div>
    </div>

    <Teleport to="body">
      <div
        v-if="showCopyButton"
        class="fixed z-[9999] translate-x-[-50%] translate-y-[calc(-100%_-_8px)]"
        :style="copyButtonStyle"
        @mousedown.stop
      >
        <NButton size="small" type="primary" @click.stop="copySelection">复制</NButton>
      </div>
    </Teleport>

    <TerminalCompletionPopover
      :active-index="completion.activeIndex.value"
      :anchor-style="completion.anchorStyle.value"
      :dark="settingsStore.isDark"
      :items="completion.items.value"
      :visible="completion.visible.value"
      @hover="setActiveCompletion"
      @select="completion.accept"
    />

    <TerminalSettingsModal v-model:show="showSettings" />
    <TerminalSnippetsModal
      v-model:show="showSnippets"
      @changed="completion.refreshSnippets"
      @select="insertSnippet"
    />
  </div>
</template>

<style scoped>
.terminal-host :deep(.xterm),
.terminal-host :deep(.xterm-viewport),
.terminal-host :deep(.xterm-screen) {
  border-radius: inherit;
  background-color: transparent;
}

.terminal-host :deep(.xterm-viewport) {
  overflow: auto;
}
</style>
