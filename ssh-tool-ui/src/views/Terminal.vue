<template>
  <div class="h-full w-full bg-black flex flex-col overflow-hidden relative">
    <div ref="terminalContainer" class="flex-1 w-full h-full"></div>

    <!-- Settings Button -->
    <div class="absolute top-2 right-4 z-10 opacity-50 hover:opacity-100 transition-opacity">
      <Dialog>
        <DialogTrigger as-child>
          <Button variant="ghost" size="icon" class="h-8 w-8 text-white hover:bg-white/20">
            <Settings class="h-5 w-5" />
          </Button>
        </DialogTrigger>
        <DialogContent class="sm:max-w-[425px] bg-zinc-900 text-white border-zinc-800">
          <DialogHeader>
            <DialogTitle>终端设置</DialogTitle>
            <DialogDescription class="text-zinc-400">
              调整终端的显示偏好设置。
            </DialogDescription>
          </DialogHeader>
          <div class="grid gap-4 py-4">
            <div class="grid grid-cols-4 items-center gap-4">
              <Label for="font-size" class="text-right">
                字体大小
              </Label>
              <Input id="font-size" type="number" v-model.number="settingsStore.terminalFontSize"
                class="col-span-3 bg-zinc-800 border-zinc-700 text-white" min="8" max="72" />
            </div>
            <div class="grid grid-cols-4 items-center gap-4">
              <Label for="font-family" class="text-right">
                字体名称
              </Label>
              <Input id="font-family" v-model="settingsStore.terminalFontFamily"
                class="col-span-3 bg-zinc-800 border-zinc-700 text-white" placeholder="例如: Menlo, monospace" />
            </div>
          </div>
          <DialogFooter>
            <Button @click="resetSettings" variant="outline"
              class="mr-auto text-black dark:text-white border-zinc-700 hover:bg-zinc-800">
              重置默认
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, nextTick, watch } from 'vue';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import '@xterm/xterm/css/xterm.css';
import { useSshStore } from '../stores/ssh';
import { useSettingsStore } from '../stores/settings';
import { useDesktopStore } from '../stores/desktop';
import { Settings } from 'lucide-vue-next';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

const props = defineProps<{
  windowId?: string
}>();

const terminalContainer = ref<HTMLElement | null>(null);
const sshStore = useSshStore();
const settingsStore = useSettingsStore();
const desktopStore = useDesktopStore();
let term: Terminal | null = null;
let fitAddon: FitAddon | null = null;
let socket: WebSocket | null = null;
let resizeObserver: ResizeObserver | null = null;
const mySessionId = ref<string | null>(null);

const resetSettings = () => {
  settingsStore.resetTerminalSettings();
};

watch(() => settingsStore.terminalFontSize, (newSize) => {
  if (term) {
    term.options.fontSize = newSize;
    fitAddon?.fit();
    sendResize(term.cols, term.rows);
  }
});

watch(() => settingsStore.terminalFontFamily, (newFamily) => {
  if (term) {
    term.options.fontFamily = newFamily;
    fitAddon?.fit();
    sendResize(term.cols, term.rows);
  }
});

watch(() => desktopStore.activeWindowId, (newId) => {
  if (props.windowId && newId === props.windowId) {
    term?.focus();
  }
});

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
    fontSize: settingsStore.terminalFontSize,
    fontFamily: settingsStore.terminalFontFamily,
    allowProposedApi: true
  });

  fitAddon = new FitAddon();
  term.loadAddon(fitAddon);

  if (terminalContainer.value) {
      term.open(terminalContainer.value);
      term.focus();

      // Initial fit
      setTimeout(() => {
        fitAddon?.fit();
        term?.focus();
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
    // term?.write('\r\n已连接到服务器...\r\n');
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
