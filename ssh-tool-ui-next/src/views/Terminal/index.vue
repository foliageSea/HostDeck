<script setup lang="ts">
import { computed, ref } from 'vue'
import '@xterm/xterm/css/xterm.css'
import TerminalSettingsModal from './components/TerminalSettingsModal.vue'
import { useTerminalSession } from './hooks/useTerminalSession'
import { useSshStore } from '@/stores/ssh'
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
  closeSessionOnUnmount?: boolean
  closeConnectionOnUnmount?: boolean
}>()

const sshStore = useSshStore()
const settingsStore = useSettingsStore()
const showSettings = ref(false)
const showCopyButton = ref(false)
const selectedText = ref('')
const copyButtonStyle = ref({ left: '0px', top: '0px' })
const { terminal, terminalContainer } = useTerminalSession(props)
const sessionMeta = computed(() => {
  if (props.host || props.username) {
    return {
      host: props.host ?? '',
      username: props.username ?? '',
    }
  }

  return {
    host: sshStore.host,
    username: sshStore.username,
  }
})

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
  <div class="relative flex h-full flex-col" :class="[
    settingsStore.isDark
      ? 'bg-[radial-gradient(circle_at_top,rgba(15,23,42,0.55),#020617_72%)]'
      : 'bg-[radial-gradient(circle_at_top,rgba(255,255,255,0.82),#f8fafc_72%)]',
  ]" @mousedown="showCopyButton = false" @mouseup="openCopyButton">
    <div class="flex items-center justify-between gap-[12px] border-b px-[14px] py-[10px]" :class="[
      settingsStore.isDark
        ? 'border-[rgba(148,163,184,0.14)] bg-[rgba(2,6,23,0.72)] text-[#cbd5e1]'
        : 'border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.74)] text-[#334155]',
    ]">
      <div class="flex min-w-0 items-center gap-[10px] text-[13px]">
        <span>{{ sessionMeta.username || 'unknown' }}@{{ sessionMeta.host || 'localhost' }}</span>
        <span v-if="cwd" class="truncate-line"
          :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(71,85,105,0.88)]'">{{ cwd
          }}</span>
      </div>

      <NButton quaternary size="small" @click="showSettings = true">终端设置</NButton>
    </div>

    <div
      class="terminal-surface min-h-0 flex-1 overflow-hidden rounded-[18px] border mx-[12px] mb-[12px] mt-[10px]"
      :class="[
        settingsStore.isDark
          ? 'border-[rgba(148,163,184,0.14)] bg-[#050816] shadow-[0_20px_48px_rgba(2,6,23,0.32)]'
          : 'border-[rgba(148,163,184,0.18)] bg-[#0f172a] shadow-[0_18px_42px_rgba(15,23,42,0.14)]',
      ]"
    >
      <div ref="terminalContainer" class="terminal-host h-full min-h-0 overflow-hidden rounded-[inherit] px-2" />
    </div>

    <Teleport to="body">
      <div v-if="showCopyButton" class="fixed z-[9999] translate-x-[-50%] translate-y-[calc(-100%_-_8px)]"
        :style="copyButtonStyle" @mousedown.stop>
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
}

.terminal-host :deep(.xterm-viewport) {
  overflow: auto;
}
</style>
