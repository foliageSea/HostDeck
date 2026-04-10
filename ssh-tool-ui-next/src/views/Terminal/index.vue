<script setup lang="ts">
import { ref } from 'vue'
import '@xterm/xterm/css/xterm.css'
import TerminalSettingsModal from './components/TerminalSettingsModal.vue'
import { useTerminalSession } from './hooks/useTerminalSession'
import { useSshStore } from '@/stores/ssh'
import { useSettingsStore } from '@/stores/settings'
import { getUiApi } from '@/lib/ui'

const props = defineProps<{
  windowId?: string
  sessionId?: string
  cwd?: string
}>()

const sshStore = useSshStore()
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
  <div class="terminal-view" :class="{ 'terminal-view-light': !settingsStore.isDark }" @mousedown="showCopyButton = false" @mouseup="openCopyButton">
    <div class="terminal-toolbar">
      <div class="terminal-meta">
        <span>{{ sshStore.username || 'unknown' }}@{{ sshStore.host || 'localhost' }}</span>
        <span v-if="cwd" class="terminal-cwd">{{ cwd }}</span>
      </div>

      <NButton quaternary size="small" @click="showSettings = true">终端设置</NButton>
    </div>

    <div ref="terminalContainer" class="terminal-container" />

    <Teleport to="body">
      <div
        v-if="showCopyButton"
        class="copy-floating"
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
.terminal-view {
  position: relative;
  display: flex;
  flex-direction: column;
  height: 100%;
  background: radial-gradient(circle at top, rgba(15, 23, 42, 0.55), #020617 72%);
}

.terminal-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 10px 14px;
  border-bottom: 1px solid rgba(148, 163, 184, 0.14);
  color: #cbd5e1;
  background: rgba(2, 6, 23, 0.72);
}

.terminal-meta {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
  font-size: 13px;
}

.terminal-cwd {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: rgba(148, 163, 184, 0.92);
}

.terminal-container {
  flex: 1;
  min-height: 0;
  padding: 12px;
}

.copy-floating {
  position: fixed;
  z-index: 9999;
  transform: translate(-50%, calc(-100% - 8px));
}

.terminal-view-light {
  background: radial-gradient(circle at top, rgba(255, 255, 255, 0.82), #f8fafc 72%);
}

.terminal-view-light .terminal-toolbar {
  border-bottom-color: rgba(148, 163, 184, 0.22);
  color: #334155;
  background: rgba(255, 255, 255, 0.74);
}

.terminal-view-light .terminal-cwd {
  color: rgba(71, 85, 105, 0.88);
}
</style>
