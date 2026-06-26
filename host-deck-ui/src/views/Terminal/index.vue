<script setup lang="ts">
import { ref } from 'vue'
import { Help, Settings } from '@vicons/carbon'
import '@xterm/xterm/css/xterm.css'
import TerminalSettingsModal from './components/TerminalSettingsModal.vue'
import { useTerminalSession } from './hooks/useTerminalSession'
import { useSettingsStore } from '@/stores/settings'
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
const showSettings = ref(false)
const showCopyButton = ref(false)
const selectedText = ref('')
const copyButtonStyle = ref({ left: '0px', top: '0px' })
const { terminal, terminalContainer } = useTerminalSession(props)

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
  settingsStore.setTerminalFontSize(
    settingsStore.terminalFontSize + (event.deltaY < 0 ? 1 : -1),
  )
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
    <div class="absolute right-[20px] top-[18px] z-10 flex items-center gap-[8px]">
      <NPopover trigger="hover" placement="bottom-end">
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
        </div>
      </NPopover>

      <NTooltip trigger="hover">
        <template #trigger>
          <NButton
            quaternary
            circle
            size="small"
            aria-label="终端设置"
            @click="showSettings = true"
          >
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

    <div
      class="terminal-surface min-h-0 flex-1 overflow-hidden rounded-[18px] border mx-[12px] mb-[12px] mt-[10px]"
    >
      <div
        ref="terminalContainer"
        class="terminal-host h-full min-h-0 overflow-hidden rounded-[inherit] px-2"
      />
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

    <TerminalSettingsModal v-model:show="showSettings" />
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
