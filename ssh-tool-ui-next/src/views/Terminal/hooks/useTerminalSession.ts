import { markRaw, nextTick, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'
import { FitAddon } from '@xterm/addon-fit'
import { WebLinksAddon } from '@xterm/addon-web-links'
import { Terminal } from '@xterm/xterm'
import { terminalApi } from '@/api/terminal'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'

interface TerminalProps {
  windowId?: string
  connectionId?: string
  sessionId?: string
  cwd?: string
  startupCommand?: string
  closeSessionOnUnmount?: boolean
  closeConnectionOnUnmount?: boolean
}

export function useTerminalSession(props: TerminalProps) {
  const sshStore = useSshStore()
  const settingsStore = useSettingsStore()
  const desktopStore = useDesktopStore()
  const terminalContainer = ref<HTMLElement | null>(null)
  const terminalRef = shallowRef<Terminal | null>(null)

  let fitAddon: FitAddon | null = null
  let webLinksAddon: WebLinksAddon | null = null
  let socket: WebSocket | null = null
  let resizeObserver: ResizeObserver | null = null
  let ownedSessionId: string | null = null
  let initializedCwd = false

  function fitTerminal() {
    fitAddon?.fit()
    if (terminalRef.value && socket?.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify({ cols: terminalRef.value.cols, rows: terminalRef.value.rows, type: 'resize' }))
    }
  }

  function buildTerminalSocketUrl(sessionId: string) {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    return `${protocol}//${window.location.host}/socket.io?sessionId=${sessionId}`
  }

  function shellQuotePosix(value: string) {
    return `'${value.replace(/'/g, `'\\''`)}'`
  }

  async function resolveTerminalSession() {
    if (props.sessionId) {
      return props.sessionId
    }

    const connectionId = props.connectionId ?? sshStore.connectionId

    if (!connectionId) {
      throw new Error('当前没有可用的 SSH 连接。')
    }

    const response = await terminalApi.createSession({
      connectionId,
      cols: terminalRef.value?.cols || 80,
      rows: terminalRef.value?.rows || 24,
    })

    ownedSessionId = response.sessionId
    return response.sessionId
  }

  function bindSocket(sessionId: string) {
    socket = new WebSocket(buildTerminalSocketUrl(sessionId))

    socket.onopen = () => {
      fitTerminal()
      terminalRef.value?.focus()

      if (!initializedCwd && props.cwd) {
        initializedCwd = true
        socket?.send(`cd ${shellQuotePosix(props.cwd)}\r`)
      }

      if (props.startupCommand) {
        window.setTimeout(() => {
          socket?.send(`${props.startupCommand}\r`)
        }, 1000)
      }
    }

    socket.onmessage = (event) => {
      terminalRef.value?.write(typeof event.data === 'string' ? event.data : '')
    }

    socket.onclose = () => {
      terminalRef.value?.write('\r\n连接已关闭。\r\n')
    }

    socket.onerror = (error) => {
      console.error('Terminal socket error', error)
      terminalRef.value?.write('\r\n终端连接失败。\r\n')
    }

    terminalRef.value?.onData((data) => {
      socket?.send(data)
    })
  }

  function createTerminal() {
    terminalRef.value = markRaw(new Terminal({
      allowProposedApi: true,
      cursorBlink: true,
      fontFamily: settingsStore.terminalFontFamily,
      fontSize: settingsStore.terminalFontSize,
      theme: {
        background: '#050816',
        foreground: '#e2e8f0',
      },
    }))

    fitAddon = markRaw(new FitAddon())
    webLinksAddon = markRaw(new WebLinksAddon((event, uri) => {
      event.preventDefault()
      window.open(uri, '_blank', 'noopener')
    }))

    terminalRef.value.loadAddon(fitAddon)
    terminalRef.value.loadAddon(webLinksAddon)
  }

  watch(
    () => settingsStore.terminalFontSize,
    (value) => {
      if (!terminalRef.value) {
        return
      }

      terminalRef.value.options.fontSize = value
      fitTerminal()
    },
  )

  watch(
    () => settingsStore.terminalFontFamily,
    (value) => {
      if (!terminalRef.value) {
        return
      }

      terminalRef.value.options.fontFamily = value
      fitTerminal()
    },
  )

  watch(
    () => desktopStore.activeWindowId,
    (activeWindowId) => {
      if (props.windowId && activeWindowId === props.windowId) {
        window.setTimeout(() => {
          fitTerminal()
          terminalRef.value?.focus()
        }, 16)
      }
    },
  )

  onMounted(async () => {
    if (!sshStore.isConnected || !terminalContainer.value) {
      return
    }

    await nextTick()

    createTerminal()
    if (!terminalRef.value || !terminalContainer.value) {
      return
    }

    terminalRef.value.open(terminalContainer.value)
    fitTerminal()
    terminalRef.value.focus()

    resizeObserver = new ResizeObserver(() => {
      fitTerminal()
    })
    resizeObserver.observe(terminalContainer.value)

    try {
      const sessionId = await resolveTerminalSession()
      bindSocket(sessionId)
    } catch (error) {
      const message = error instanceof Error ? error.message : '创建终端会话失败。'
      terminalRef.value.write(`\r\n错误：${message}\r\n`)
    }
  })

  onBeforeUnmount(async () => {
    const sessionIdToClose = ownedSessionId ?? (props.closeSessionOnUnmount ? props.sessionId ?? null : null)

    resizeObserver?.disconnect()
    socket?.close()
    terminalRef.value?.dispose()
    webLinksAddon = null
    fitAddon = null
    socket = null
    resizeObserver = null

    if (sessionIdToClose) {
      try {
        await terminalApi.deleteSession(sessionIdToClose)
      } catch (error) {
        console.error('Failed to delete terminal session', error)
      }
    }

  })

  return {
    terminal: terminalRef,
    terminalContainer,
  }
}
