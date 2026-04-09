<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { FitAddon } from '@xterm/addon-fit'
import { WebLinksAddon } from '@xterm/addon-web-links'
import { Terminal } from '@xterm/xterm'
import '@xterm/xterm/css/xterm.css'
import { terminalApi } from '@/api/terminal'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'
import { getUiApi } from '@/lib/ui'

const props = defineProps<{
  windowId?: string
  sessionId?: string
  cwd?: string
}>()

const sshStore = useSshStore()
const settingsStore = useSettingsStore()
const desktopStore = useDesktopStore()

const terminalContainer = ref<HTMLElement | null>(null)
const showSettings = ref(false)
const showCopyButton = ref(false)
const selectedText = ref('')
const copyButtonStyle = ref({ left: '0px', top: '0px' })

let terminal: Terminal | null = null
let fitAddon: FitAddon | null = null
let webLinksAddon: WebLinksAddon | null = null
let socket: WebSocket | null = null
let resizeObserver: ResizeObserver | null = null
let ownedSessionId: string | null = null
let initializedCwd = false

watch(
  () => settingsStore.terminalFontSize,
  (value) => {
    if (!terminal) {
      return
    }

    terminal.options.fontSize = value
    fitTerminal()
  },
)

watch(
  () => settingsStore.terminalFontFamily,
  (value) => {
    if (!terminal) {
      return
    }

    terminal.options.fontFamily = value
    fitTerminal()
  },
)

watch(
  () => desktopStore.activeWindowId,
  (activeWindowId) => {
    if (props.windowId && activeWindowId === props.windowId) {
      window.setTimeout(() => {
        fitTerminal()
        terminal?.focus()
      }, 16)
    }
  },
)

function fitTerminal() {
  fitAddon?.fit()
  if (terminal) {
    sendResize(terminal.cols, terminal.rows)
  }
}

function buildTerminalSocketUrl(sessionId: string) {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
  return `${protocol}//${window.location.host}/socket.io?sessionId=${sessionId}`
}

function shellQuotePosix(value: string) {
  return `'${value.replace(/'/g, `'\\''`)}'`
}

function openCopyButton(event: MouseEvent) {
  if (!terminal?.hasSelection()) {
    showCopyButton.value = false
    return
  }

  const selection = terminal.getSelection()
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
    terminal?.clearSelection()
    showCopyButton.value = false
  } catch (error) {
    console.error('Failed to copy terminal text', error)
    getUiApi().message.error('复制失败。')
  }
}

function sendResize(cols: number, rows: number) {
  if (socket?.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify({ cols, rows, type: 'resize' }))
  }
}

async function resolveTerminalSession() {
  if (props.sessionId) {
    return props.sessionId
  }

  if (!sshStore.connectionId) {
    throw new Error('当前没有可用的 SSH 连接。')
  }

  const response = await terminalApi.createSession({
    connectionId: sshStore.connectionId,
    cols: terminal?.cols || 80,
    rows: terminal?.rows || 24,
  })

  ownedSessionId = response.sessionId
  return response.sessionId
}

function bindSocket(sessionId: string) {
  socket = new WebSocket(buildTerminalSocketUrl(sessionId))

  socket.onopen = () => {
    fitTerminal()
    terminal?.focus()

    if (!initializedCwd && props.cwd) {
      initializedCwd = true
      socket?.send(`cd ${shellQuotePosix(props.cwd)}\r`)
    }
  }

  socket.onmessage = (event) => {
    terminal?.write(typeof event.data === 'string' ? event.data : '')
  }

  socket.onclose = () => {
    terminal?.write('\r\n连接已关闭。\r\n')
  }

  socket.onerror = (error) => {
    console.error('Terminal socket error', error)
    terminal?.write('\r\n终端连接失败。\r\n')
  }

  terminal?.onData((data) => {
    socket?.send(data)
  })
}

function createTerminal() {
  terminal = new Terminal({
    allowProposedApi: true,
    cursorBlink: true,
    fontFamily: settingsStore.terminalFontFamily,
    fontSize: settingsStore.terminalFontSize,
    theme: {
      background: '#050816',
      foreground: '#e2e8f0',
    },
  })

  fitAddon = new FitAddon()
  webLinksAddon = new WebLinksAddon((event, uri) => {
    event.preventDefault()
    window.open(uri, '_blank', 'noopener')
  })

  terminal.loadAddon(fitAddon)
  terminal.loadAddon(webLinksAddon)
}

onMounted(async () => {
  if (!sshStore.isConnected || !terminalContainer.value) {
    return
  }

  await nextTick()

  createTerminal()
  const currentTerminal = terminal
  if (!currentTerminal) {
    return
  }

  currentTerminal.open(terminalContainer.value)
  fitTerminal()
  currentTerminal.focus()

  resizeObserver = new ResizeObserver(() => {
    fitTerminal()
  })
  resizeObserver.observe(terminalContainer.value)

  try {
    const sessionId = await resolveTerminalSession()
    bindSocket(sessionId)
  } catch (error) {
    const message = error instanceof Error ? error.message : '创建终端会话失败。'
    currentTerminal.write(`\r\n错误：${message}\r\n`)
  }
})

onBeforeUnmount(async () => {
  resizeObserver?.disconnect()
  socket?.close()
  webLinksAddon?.dispose()
  fitAddon?.dispose()
  terminal?.dispose()

  if (ownedSessionId) {
    try {
      await terminalApi.deleteSession(ownedSessionId)
    } catch (error) {
      console.error('Failed to delete terminal session', error)
    }
  }
})
</script>

<template>
  <div class="terminal-view" @mousedown="showCopyButton = false" @mouseup="openCopyButton">
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

    <NModal v-model:show="showSettings" preset="card" title="终端设置" class="terminal-settings-modal">
      <NSpace vertical size="large">
        <div>
          <div class="setting-label">字体大小</div>
          <NSlider
            :value="settingsStore.terminalFontSize"
            :min="8"
            :max="32"
            @update:value="(value: number) => settingsStore.setTerminalFontSize(value)"
          />
        </div>

        <div>
          <div class="setting-label">字体名称</div>
          <NInput
            :value="settingsStore.terminalFontFamily"
            placeholder="例如 Consolas, monospace"
            @update:value="(value: string) => settingsStore.setTerminalFontFamily(value)"
          />
        </div>

        <NSpace justify="end">
          <NButton @click="settingsStore.resetTerminalSettings()">恢复默认</NButton>
          <NButton type="primary" @click="showSettings = false">完成</NButton>
        </NSpace>
      </NSpace>
    </NModal>
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

.terminal-settings-modal {
  width: min(460px, calc(100vw - 24px));
}

.setting-label {
  margin-bottom: 10px;
  font-size: 13px;
  color: rgba(148, 163, 184, 0.92);
}
</style>
