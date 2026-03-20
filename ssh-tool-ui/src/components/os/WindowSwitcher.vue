<template>
  <div class="fixed inset-0 flex items-center justify-center z-[99999] bg-black/20 backdrop-blur-sm">
    <div
      class="bg-background/80 backdrop-blur-md border border-border rounded-xl shadow-2xl p-4 flex flex-col gap-4 min-w-[300px] max-w-[800px] animate-in zoom-in-95 duration-200 ease-out">
      <div class="text-sm font-medium text-muted-foreground px-2">切换窗口</div>
      <div class="flex flex-wrap gap-4 justify-center">
        <div v-for="(window, index) in windows" :key="window.id"
          class="flex flex-col items-center gap-2 p-4 rounded-lg cursor-pointer transition-all duration-300 ease-out w-32 h-32 justify-center border-2"
          :class="[
            selectedIndex === index
              ? 'bg-accent border-primary shadow-xl scale-110'
              : 'bg-card border-transparent hover:bg-accent/50 hover:scale-105'
          ]" @click="$emit('select', index)">
          <div class="w-12 h-12 flex items-center justify-center bg-card text-card-foreground rounded-xl shadow-sm transition-transform duration-300"
            :class="selectedIndex === index ? 'scale-110' : ''">
            <component v-if="iconMap[window.icon]" :is="iconMap[window.icon]" class="w-6 h-6" />
            <img v-else-if="window.icon.startsWith('http')" :src="window.icon" class="w-full h-full object-cover" />
            <span v-else>{{ window.icon }}</span>
          </div>
          <span class="text-xs text-center font-medium line-clamp-2 w-full break-words">
            {{ window.title }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { type WindowState } from '@/stores/desktop';
import { Terminal, Folder, Activity, Lock, FileText } from 'lucide-vue-next';

defineProps<{
  windows: WindowState[];
  selectedIndex: number;
}>();

defineEmits<{
  (e: 'select', index: number): void;
}>();

const iconMap: Record<string, any> = {
  'terminal': Terminal,
  'folder': Folder,
  'activity': Activity,
  'lock': Lock,
  'file-text': FileText
};
</script>
