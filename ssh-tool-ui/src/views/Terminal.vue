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
const mySessionId = ref<string | null>(null);

onMounted(async () => {
  if (!sshStore.isConnected) {
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

  // Create new session
  try {
      if (sshStore.connectionId) {
          const res = await fetch('/api/terminal/session', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ connectionId: sshStore.connectionId })
          });
          if (!res.ok) {
              term?.write(`\r\n错误：创建会话失败 - ${await res.text()}\r\n`);
              return;
          }
          const data = await res.json();
          mySessionId.value = data.sessionId;
      } else if (sshStore.sessionId) {
          mySessionId.value = sshStore.sessionId;
      } else {
          term?.write('\r\n错误：未连接\r\n');
          return;
      }
  } catch (e) {
      term?.write(`\r\n错误：连接异常 - ${e}\r\n`);
      return;
  }

  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsUrl = `${protocol}//${window.location.host}/socket.io?sessionId=${mySessionId.value}`;
  
  socket = new WebSocket(wsUrl);
  
  socket.onopen = () => {
    term?.write('\r\n已连接到服务器...\r\n');
    fitAddon?.fit();
    if (term) {
        sendResize(term.cols, term.rows);
    }
  };
  
  socket.onmessage = (event) => {
      term?.write(event.data);
  };
  
  socket.onclose = () => {
    term?.write('\r\n已断开连接。\r\n');
  };
  
  socket.onerror = (err) => {
    term?.write(`\r\n错误：连接失败\r\n`);
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

onBeforeUnmount(async () => {
  resizeObserver?.disconnect();
  socket?.close();
  term?.dispose();
  
  // Close session if it's a dedicated one
  if (mySessionId.value && mySessionId.value !== sshStore.sessionId) {
      try {
          await fetch(`/api/terminal/session?sessionId=${mySessionId.value}`, {
              method: 'DELETE'
          });
      } catch (e) {
          console.error('Failed to close session', e);
      }
  }
});
</script>
