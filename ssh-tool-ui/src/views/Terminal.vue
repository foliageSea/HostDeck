<template>
  <div class="h-full w-full bg-black flex flex-col overflow-hidden relative" @mouseup="handleMouseUp"
    @mousedown="handleMouseDown">
    <div ref="terminalContainer" class="flex-1 w-full h-full pl-2 pr-2"></div>

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

    <!-- Copy Button -->
    <Teleport to="body">
      <div v-if="showCopyBtn" :style="copyBtnStyle" @mousedown.stop
        class="fixed z-[9999] transform -translate-x-1/2 -translate-y-full pb-2 pointer-events-none">
        <div class="pointer-events-auto">
          <Button size="sm" @click.stop="copySelection"
            class="shadow-lg h-8 px-3 bg-zinc-800 hover:bg-zinc-700 text-white border border-zinc-700">
            <Copy class="w-3.5 h-3.5 mr-2" />
            复制
          </Button>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, nextTick, watch } from 'vue';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { WebLinksAddon } from '@xterm/addon-web-links';
import '@xterm/xterm/css/xterm.css';
import { useSshStore } from '../stores/ssh';
import { useSettingsStore } from '../stores/settings';
import { useDesktopStore } from '../stores/desktop';
import { toast } from 'vue-sonner';
import { Settings, Copy } from 'lucide-vue-next';
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
import { terminalApi } from '@/api/terminal';

const props = defineProps<{
  windowId?: string
  sessionId?: string
}>();

const terminalContainer = ref<HTMLElement | null>(null);
const sshStore = useSshStore();
const settingsStore = useSettingsStore();
const desktopStore = useDesktopStore();
const showCopyBtn = ref(false);
const copyBtnStyle = ref({ top: '0px', left: '0px' });
const selectedText = ref('');

const handleMouseUp = (e: MouseEvent) => {
  if (!term) return;
  if (term.hasSelection()) {
    const selection = term.getSelection();
    if (selection) {
      selectedText.value = selection;
      
      let top = e.clientY;
      let left = e.clientX;
      
      // 防止按钮超出屏幕顶部或两侧
      if (top < 40) top = 40;
      if (left < 50) left = 50;
      if (left > window.innerWidth - 50) left = window.innerWidth - 50;

      copyBtnStyle.value = {
        top: `${top}px`,
        left: `${left}px`
      };
      showCopyBtn.value = true;
    }
  } else {
    showCopyBtn.value = false;
  }
};

const handleMouseDown = () => {
  showCopyBtn.value = false;
};

const copySelection = async () => {
  if (selectedText.value) {
    try {
      await navigator.clipboard.writeText(selectedText.value);
      toast.success('已复制');
      showCopyBtn.value = false;
      if (term) term.clearSelection();
    } catch (e) {
      console.error('Copy failed', e);
      toast.error('复制失败');
    }
  }
};

let term: Terminal | null = null;
let fitAddon: FitAddon | null = null;
let webLinksAddon: WebLinksAddon | null = null;
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

  webLinksAddon = new WebLinksAddon((event, uri) => {
    // 阻止默认行为，防止终端失去焦点或其他意外行为
    event.preventDefault();
    // 使用默认浏览器打开链接
    window.open(uri, '_blank');
  });
  term.loadAddon(webLinksAddon);

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
    if (props.sessionId) {
      mySessionId.value = props.sessionId;
    } else if (sshStore.connectionId) {
      const data = await terminalApi.createSession({
        connectionId: sshStore.connectionId,
        cols: term?.cols || 80,
        rows: term?.rows || 24
      });
      mySessionId.value = data.sessionId;
    } else if (sshStore.sessionId) {
      mySessionId.value = sshStore.sessionId;
    } else {
      term?.write('\r\n错误：未连接\r\n');
      return;
    }
  } catch (e: any) {
    term?.write(`\r\n错误：创建会话失败 - ${e.response?.data || e.message}\r\n`);
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
  webLinksAddon?.dispose();
  fitAddon?.dispose();
  term?.dispose();

  // Close session if it's a dedicated one created by this view.
  // If sessionId is passed in, lifecycle is owned by the creator.
  if (!props.sessionId && mySessionId.value && mySessionId.value !== sshStore.sessionId) {
    try {
      await terminalApi.deleteSession(mySessionId.value);
    } catch (e) {
      console.error('Failed to close session', e);
    }
  }
});
</script>
