<template>
  <div 
    class="absolute flex flex-col bg-white shadow-2xl overflow-hidden select-none"
    :class="[
      window.isMaximized ? 'rounded-none border-0' : 'rounded-lg border border-gray-200',
      (isDragging || isResizing) ? '' : 'transition-all duration-200 ease-in-out'
    ]"
    :style="window.isMaximized ? {
      left: '0px',
      top: '0px',
      width: '100%',
      height: '100%',
      zIndex: window.zIndex,
      display: window.isMinimized ? 'none' : 'flex'
    } : {
      left: `${window.x}px`,
      top: `${window.y}px`,
      width: `${window.width}px`,
      height: `${window.height}px`,
      zIndex: window.zIndex,
      display: window.isMinimized ? 'none' : 'flex'
    }"
    @mousedown="focusWindow"
  >
    <!-- Title Bar -->
    <div 
      :class="['h-8 bg-gray-100 border-b border-gray-200 flex items-center justify-between px-3', window.isMaximized ? 'cursor-default' : 'cursor-move']"
      @mousedown.prevent="startDrag"
      @dblclick="maximizeWindow"
    >
      <div class="flex items-center space-x-2">
        <!-- Controls -->
        <button 
          @click.stop="closeWindow"
          class="w-3 h-3 rounded-full bg-red-500 hover:bg-red-600 transition-colors flex items-center justify-center group"
        >
          <span class="text-[8px] text-red-900 opacity-0 group-hover:opacity-100">x</span>
        </button>
        <button 
          @click.stop="minimizeWindow"
          class="w-3 h-3 rounded-full bg-yellow-500 hover:bg-yellow-600 transition-colors flex items-center justify-center group"
        >
          <span class="text-[8px] text-yellow-900 opacity-0 group-hover:opacity-100">-</span>
        </button>
        <button 
          @click.stop="maximizeWindow"
          class="w-3 h-3 rounded-full bg-green-500 hover:bg-green-600 transition-colors flex items-center justify-center group"
        >
          <span class="text-[8px] text-green-900 opacity-0 group-hover:opacity-100">+</span>
        </button>
      </div>
      
      <div class="flex items-center justify-center gap-2 px-2 flex-1 min-w-0">
        <component 
          v-if="iconMap[window.icon]" 
          :is="iconMap[window.icon]" 
          class="w-3.5 h-3.5 text-gray-500" 
        />
        <span class="text-xs font-medium text-gray-600 truncate">{{ window.title }}</span>
      </div>
      
      <div class="w-12"></div> <!-- Spacer for balance -->
    </div>

    <!-- Content -->
    <div class="flex-1 overflow-hidden relative bg-white">
      <component :is="window.component" :window-id="window.id" v-bind="window.props" />
    </div>

    <!-- Resize Handles -->
    <div 
      :class="['absolute bottom-0 right-0 w-4 h-4 z-50', window.isMaximized ? 'hidden' : 'cursor-se-resize']"
      @mousedown.prevent="startResize"
    ></div>
  </div>
</template>

<script setup lang="ts">
import { ref, onUnmounted } from 'vue';
import { useDesktopStore, type WindowState } from '@/stores/desktop';
import { Terminal, Folder, Activity, Lock, FileText } from 'lucide-vue-next';

const props = defineProps<{
  window: WindowState
}>();

const desktopStore = useDesktopStore();

const iconMap: Record<string, any> = {
  'terminal': Terminal,
  'folder': Folder,
  'activity': Activity,
  'lock': Lock,
  'file-text': FileText
};

const focusWindow = () => {
  desktopStore.focusWindow(props.window.id);
};

const closeWindow = () => {
  desktopStore.closeWindow(props.window.id);
};

const minimizeWindow = () => {
  desktopStore.minimizeWindow(props.window.id);
};

const maximizeWindow = () => {
  desktopStore.maximizeWindow(props.window.id);
};

// Drag Logic
const isDragging = ref(false);
const dragOffset = ref({ x: 0, y: 0 });

const startDrag = (e: MouseEvent) => {
  if (props.window.isMaximized) return; // Can't drag maximized window
  
  focusWindow();
  isDragging.value = true;
  dragOffset.value = {
    x: e.clientX - props.window.x,
    y: e.clientY - props.window.y
  };
  
  window.addEventListener('mousemove', handleDrag);
  window.addEventListener('mouseup', stopDrag);
};

const handleDrag = (e: MouseEvent) => {
  if (!isDragging.value) return;
  
  let newX = e.clientX - dragOffset.value.x;
  let newY = e.clientY - dragOffset.value.y;
  
  // Simple bounds check (keep top bar visible)
  if (newY < 32) newY = 32; // Below top bar
  
  desktopStore.updateWindowPosition(props.window.id, newX, newY);
};

const stopDrag = () => {
  isDragging.value = false;
  window.removeEventListener('mousemove', handleDrag);
  window.removeEventListener('mouseup', stopDrag);
};

// Resize Logic
const isResizing = ref(false);
const startResize = () => {
  if (props.window.isMaximized) return;

  focusWindow();
  isResizing.value = true;
  
  window.addEventListener('mousemove', handleResize);
  window.addEventListener('mouseup', stopResize);
};

const handleResize = (e: MouseEvent) => {
  if (!isResizing.value) return;
  
  const newWidth = Math.max(300, e.clientX - props.window.x);
  const newHeight = Math.max(200, e.clientY - props.window.y);
  
  desktopStore.updateWindowSize(props.window.id, newWidth, newHeight);
};

const stopResize = () => {
  isResizing.value = false;
  window.removeEventListener('mousemove', handleResize);
  window.removeEventListener('mouseup', stopResize);
};

onUnmounted(() => {
  window.removeEventListener('mousemove', handleDrag);
  window.removeEventListener('mouseup', stopDrag);
  window.removeEventListener('mousemove', handleResize);
  window.removeEventListener('mouseup', stopResize);
});
</script>
