<template>
  <div class="h-full flex flex-col">
    <h1 class="text-xl font-bold mb-2">Terminal</h1>
    <div ref="terminalContainer" class="flex-1 bg-black rounded overflow-hidden p-2"></div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, nextTick } from 'vue'
import { Terminal } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'
import '@xterm/xterm/css/xterm.css'
import { useSshStore } from '../stores/ssh'

const terminalContainer = ref<HTMLElement | null>(null)
const sshStore = useSshStore()
let term: Terminal | null = null
let socket: WebSocket | null = null
let fitAddon: FitAddon | null = null

onMounted(async () => {
  if (!sshStore.isConnected || !sshStore.sessionId) {
    return
  }
  
  await nextTick()
  
  term = new Terminal({
    cursorBlink: true,
    theme: {
      background: '#000000',
      foreground: '#ffffff'
    },
    fontSize: 14,
    fontFamily: 'Menlo, Monaco, "Courier New", monospace'
  })
  
  fitAddon = new FitAddon()
  term.loadAddon(fitAddon)
  
  if (terminalContainer.value) {
    term.open(terminalContainer.value)
    fitAddon.fit()
  }

  // Connect to WebSocket
  // Use protocol relative URL (ws:// or wss://)
  // If we are proxying via Vite, window.location.host is localhost:5173
  // And /socket.io is proxied to localhost:8080
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
  const wsUrl = `${protocol}//${window.location.host}/socket.io?sessionId=${sshStore.sessionId}`
  
  socket = new WebSocket(wsUrl)
  
  socket.onopen = () => {
    term?.write('\r\nConnected to server...\r\n')
    // Send resize
    if (fitAddon && term) {
       sendResize(term.cols, term.rows)
    }
  }
  
  socket.onmessage = (event) => {
    if (typeof event.data === 'string') {
       term?.write(event.data)
    }
  }
  
  socket.onclose = () => {
    term?.write('\r\nDisconnected from server.\r\n')
  }
  
  socket.onerror = (err) => {
    term?.write(`\r\nError: Connection failed\r\n`)
    console.error(err)
  }
  
  term.onData(data => {
    socket?.send(data)
  })
  
  term.onResize(({ cols, rows }) => {
    sendResize(cols, rows)
  })
  
  window.addEventListener('resize', handleResize)
})

function handleResize() {
  fitAddon?.fit()
}

function sendResize(cols: number, rows: number) {
  if (socket && socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify({ type: 'resize', cols, rows }))
  }
}

onBeforeUnmount(() => {
  window.removeEventListener('resize', handleResize)
  socket?.close()
  term?.dispose()
})
</script>
