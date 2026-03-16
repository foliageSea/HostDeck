<template>
  <TooltipProvider>
    <div
      class="fixed bottom-4 left-1/2 transform -translate-x-1/2 bg-background/40 backdrop-blur-2xl border border-border/50 rounded-2xl px-4 py-2 flex items-end space-x-4 shadow-2xl z-50">
      
      <div v-for="app in apps" :key="app.id" class="relative group">
        <!-- Context Menu Wrapper -->
        <ContextMenu>
          <ContextMenuTrigger>
            <Tooltip>
              <TooltipTrigger as-child>
                <div
                  v-show="app.hide !== true" 
                  class="relative flex flex-col items-center cursor-pointer transition-all duration-300 hover:scale-110" 
                  @click="handleAppClick(app.id)"
                >
                  <div
                    class="w-12 h-12 rounded-xl flex items-center justify-center text-3xl shadow-lg bg-card text-card-foreground relative overflow-hidden border border-border">
                    <!-- Icon Placeholder -->
                    <component v-if="iconMap[app.icon]" :is="iconMap[app.icon]" class="w-6 h-6 " />
                    <img v-else-if="app.icon.startsWith('http')" :src="app.icon" class="w-full h-full object-cover" />
                    <span v-else>{{ app.icon }}</span>
                  </div>

                  <!-- Indicator for open apps -->
                  <div v-if="isAppOpen(app.id)" class="w-1 h-1 bg-primary rounded-full mt-1"></div>
                </div>
              </TooltipTrigger>
              <TooltipContent>
                <p>{{ app.title }}</p>
              </TooltipContent>
            </Tooltip>
          </ContextMenuTrigger>
          
          <ContextMenuContent>
            <ContextMenuItem @click="openNewWindow(app.id)">
              新建窗口
            </ContextMenuItem>
            <ContextMenuItem v-if="getAppWindows(app.id).length > 0" @click="closeAppWindows(app.id)" class="text-red-500 focus:text-red-500">
              关闭所有窗口
            </ContextMenuItem>
          </ContextMenuContent>
        </ContextMenu>

        <!-- Window Selector Popover -->
        <div v-if="showSelector === app.id" class="absolute bottom-full left-1/2 -translate-x-1/2 mb-4 w-48 z-[60]">
          <!-- Backdrop to close on click outside -->
          <div class="fixed inset-0 z-40" @click.stop="showSelector = null"></div>
          
          <div class="relative z-50 flex flex-col bg-popover text-popover-foreground rounded-md border shadow-md overflow-hidden animate-in fade-in zoom-in-95 duration-200">
            <div class="px-2 py-1.5 text-xs font-semibold text-muted-foreground border-b bg-muted/50">
              选择窗口
            </div>
            <div class="max-h-[200px] overflow-y-auto p-1">
              <button
                v-for="window in getAppWindows(app.id)"
                :key="window.id"
                class="w-full text-left px-2 py-1.5 text-sm rounded-sm hover:bg-accent hover:text-accent-foreground flex items-center gap-2 transition-colors truncate"
                @click="activateWindow(window.id)"
              >
                <span class="truncate flex-1">{{ window.title }}</span>
                <span v-if="desktopStore.activeWindowId === window.id" class="w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0"></span>
              </button>
            </div>
          </div>
          <!-- Arrow -->
          <div class="absolute -bottom-1.5 left-1/2 -translate-x-1/2 w-3 h-3 bg-popover border-r border-b border-border rotate-45 z-50"></div>
        </div>
      </div>
    </div>
  </TooltipProvider>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue';
import { useDesktopStore } from '@/stores/desktop';
import { Terminal, Folder, Activity, Lock, FileText } from 'lucide-vue-next';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip'
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuTrigger,
} from '@/components/ui/context-menu'

const desktopStore = useDesktopStore();

const apps = computed(() => Object.values(desktopStore.apps));
const showSelector = ref<string | null>(null);

const iconMap: Record<string, any> = {
  'terminal': Terminal,
  'folder': Folder,
  'activity': Activity,
  'lock': Lock,
  'file-text': FileText
};

const isAppOpen = (appId: string) => {
  return desktopStore.windows.some(w => w.appId === appId);
};

const getAppWindows = (appId: string) => {
  return desktopStore.windows.filter(w => w.appId === appId);
};

const handleAppClick = (appId: string) => {
  // If selector is already open for this app, close it
  if (showSelector.value === appId) {
    showSelector.value = null;
    return;
  }
  
  // Close any other open selector
  showSelector.value = null;

  const windows = getAppWindows(appId);
  
  if (windows.length === 0) {
    // No windows: Open new
    desktopStore.openWindow(appId);
  } else if (windows.length === 1) {
    // One window: Focus it
    activateWindow(windows[0].id);
  } else {
    // Multiple windows: Show selector
    showSelector.value = appId;
  }
};

const openNewWindow = (appId: string) => {
  desktopStore.openWindow(appId);
  showSelector.value = null;
};

const activateWindow = (windowId: string) => {
  desktopStore.focusWindow(windowId);
  // Ensure it's not minimized
  const window = desktopStore.windows.find(w => w.id === windowId);
  if (window && window.isMinimized) {
    desktopStore.restoreWindow(windowId);
  }
  showSelector.value = null;
};

const closeAppWindows = (appId: string) => {
  const windows = getAppWindows(appId);
  windows.forEach(w => desktopStore.closeWindow(w.id));
  showSelector.value = null;
};
</script>
