import { markRaw, nextTick, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'
import { FitAddon } from '@xterm/addon-fit'
import { WebLinksAddon } from '@xterm/addon-web-links'
import { Terminal } from '@xterm/xterm'
import { terminalApi } from '@/api/terminal'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'

interface TerminalProps {
  windowId?: string
  connectionId?: string
  sessionId?: string
  cwd?: string
  startupCommand?: string
  openIframeAfterMs?: number
  openIframeTitle?: string
  openIframeUrl?: string
  shutdownCommand?: string
  closeSessionOnUnmount?: boolean
  closeConnectionOnUnmount?: boolean
}

function buildTerminalTheme(isDark: boolean) {
  if (isDark) {
    return {
      background: '#050816',
      black: '#0f172a',
      blue: '#60a5fa',
      brightBlack: '#475569',
      brightBlue: '#93c5fd',
      brightCyan: '#67e8f9',
      brightGreen: '#86efac',
      brightMagenta: '#f0abfc',
      brightRed: '#fca5a5',
      brightWhite: '#f8fafc',
      brightYellow: '#fde68a',
      cursor: '#e2e8f0',
      cyan: '#22d3ee',
      foreground: '#e2e8f0',
      green: '#4ade80',
      magenta: '#e879f9',
      red: '#f87171',
      selectionBackground: '#334155',
      white: '#cbd5e1',
      yellow: '#facc15',
    }
  }

  return {
    background: '#f8fafc',
    black: '#0f172a',
    blue: '#2563eb',
    brightBlack: '#64748b',
    brightBlue: '#1d4ed8',
    brightCyan: '#0e7490',
    brightGreen: '#15803d',
    brightMagenta: '#a21caf',
    brightRed: '#b91c1c',
    brightWhite: '#020617',
    brightYellow: '#a16207',
    cursor: '#0f172a',
    cyan: '#0891b2',
    foreground: '#0f172a',
    green: '#16a34a',
    magenta: '#c026d3',
    red: '#dc2626',
    selectionBackground: '#dbeafe',
    white: '#334155',
    yellow: '#ca8a04',
  }
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
  let startupCommandTimer: number | null = null
  let openIframeTimer: number | null = null

  function delay(ms: number) {
    return new Promise((resolve) => window.setTimeout(resolve, ms))
  }

  function fitTerminal() {
    fitAddon?.fit()
    if (terminalRef.value && socket?.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify({ cols: terminalRef.value.cols, rows: terminalRef.value.rows, type: 'resize' }))
    }
  }

  function buildTerminalSocketUrl(sessionId: string) {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    return `${protocol}//${window.location.host}/api/ws/terminal?sessionId=${sessionId}`
  }

  function clearStartupTimers() {
    if (startupCommandTimer !== null) {
      clearTimeout(startupCommandTimer)
      startupCommandTimer = null
    }

    if (openIframeTimer !== null) {
      clearTimeout(openIframeTimer)
      openIframeTimer = null
    }
  }

  function closeLinkedIframeWindow() {
    if (!props.openIframeUrl) {
      return
    }

    desktopStore.windows
      .filter((window) => window.appId === 'iframe-app' && window.props?.url === props.openIframeUrl)
      .forEach((window) => {
        desktopStore.closeWindow(window.id)
      })
  }

  async function shutdownTerminalProcess() {
    if (socket?.readyState !== WebSocket.OPEN) {
      return
    }

    socket.send('\x03')
    await delay(300)

    if (props.shutdownCommand) {
      socket.send(`${props.shutdownCommand}\r`)
      await delay(500)
    }
  }

  function shellQuotePosix(value: string) {
    return `'${value.replace(/'/g, `'\\''`)}'`
  }

  async function pasteClipboardToTerminal() {
    if (!navigator.clipboard?.readText) {
      getUiApi().message.error('当前环境不支持读取剪贴板。')
      return
    }

    try {
      const text = await navigator.clipboard.readText()
      if (text) {
        terminalRef.value?.paste(text)
      }
    } catch (error) {
      console.error('Failed to paste terminal clipboard text', error)
      getUiApi().message.error('粘贴失败，请检查剪贴板权限。')
    }
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
        startupCommandTimer = window.setTimeout(() => {
          startupCommandTimer = null
          socket?.send(`${props.startupCommand}\r`)

          if (props.openIframeUrl) {
            openIframeTimer = window.setTimeout(() => {
              openIframeTimer = null
              desktopStore.openWindow('iframe-app', {
                title: props.openIframeTitle ?? props.openIframeUrl,
                url: props.openIframeUrl,
              })
            }, props.openIframeAfterMs ?? 2000)
          }
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
      theme: buildTerminalTheme(settingsStore.isDark),
    }))

    terminalRef.value.attachCustomKeyEventHandler((event) => {
      if (event.type === 'keydown' && event.ctrlKey && !event.altKey && !event.metaKey && event.key.toLowerCase() === 'v') {
        event.preventDefault()
        event.stopPropagation()
        void pasteClipboardToTerminal()
        return false
      }

      return true
    })

    fitAddon = markRaw(new FitAddon())
    webLinksAddon = markRaw(new WebLinksAddon((event, uri) => {
      event.preventDefault()
      window.open(uri, '_blank', 'noopener')
    }))

    terminalRef.value.loadAddon(fitAddon)
    terminalRef.value.loadAddon(webLinksAddon)
  }

  watch(
    () => settingsStore.isDark,
    (isDark) => {
      if (!terminalRef.value) {
        return
      }

      terminalRef.value.options.theme = buildTerminalTheme(isDark)
    },
  )

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
    clearStartupTimers()
    closeLinkedIframeWindow()
    await shutdownTerminalProcess()
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
