<template>
  <div class="h-full w-full bg-black flex flex-col overflow-hidden">
    <div ref="terminalContainer" class="flex-1 w-full h-full"></div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import '@xterm/xterm/css/xterm.css';
import { useSshStore } from '../stores/ssh';

const props = defineProps<{
  windowId?: string
}>();

const terminalContainer = ref<HTMLElement | null>(null);
const sshStore = useSshStore();
let term: Terminal | null = null;
let fitAddon: FitAddon | null = null;
let socket: WebSocket | null = null;
let resizeObserver: ResizeObserver | null = null;

onMounted(async () => {
  if (!sshStore.isConnected || !sshStore.sessionId) {
    return;
  }
  
  await nextTick();
  
  term = new Terminal({
    cursorBlink: true,
    theme: {
      background: '#000000',
      foreground: '#ffffff',
    },
    fontSize: 14,
    fontFamily: 'Menlo, Monaco, "Courier New", monospace',
    allowProposedApi: true
  });
  
  fitAddon = new FitAddon();
  term.loadAddon(fitAddon);
  
  if (terminalContainer.value) {
    term.open(terminalContainer.value);
    
    // Initial fit
    setTimeout(() => {
        fitAddon?.fit();
    }, 100);

    // Resize Observer
    resizeObserver = new ResizeObserver(() => {
      fitAddon?.fit();
      if (term) {
        sendResize(term.cols, term.rows);
      }
    });
    resizeObserver.observe(terminalContainer.value);
  }

  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsUrl = `${protocol}//${window.location.host}/socket.io?sessionId=${sshStore.sessionId}`;
  
  socket = new WebSocket(wsUrl);
  
  socket.onopen = () => {
    term?.write('\r\nConnected to server...\r\n');
    fitAddon?.fit();
    if (term) {
        sendResize(term.cols, term.rows);
    }
  };
  
  socket.onmessage = (event) => {
      // Check if it is a resize ack or data
      // For now assume raw data unless we wrap it
      // The current backend implementation seems to send raw strings?
      // Wait, the previous code had `if (typeof event.data === 'string')`
      // But sendResize sends JSON stringify.
      // Backend probably handles JSON for resize but sends raw string for output.
      
      // Let's assume backend sends raw text for output.
      term?.write(event.data);
  };
  
  socket.onclose = () => {
    term?.write('\r\nDisconnected from server.\r\n');
  };
  
  socket.onerror = (err) => {
    term?.write(`\r\nError: Connection failed\r\n`);
    console.error(err);
  };
  
  term.onData(data => {
    socket?.send(data);
  });
});

function sendResize(cols: number, rows: number) {
  if (socket && socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify({ type: 'resize', cols, rows }));
  }
}

onBeforeUnmount(() => {
  resizeObserver?.disconnect();
  socket?.close();
  term?.dispose();
});
</script>
