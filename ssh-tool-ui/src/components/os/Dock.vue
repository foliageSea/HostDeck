<template>
  <div class="fixed bottom-4 left-1/2 transform -translate-x-1/2 bg-white/20 backdrop-blur-xl border border-white/20 rounded-2xl px-4 py-2 flex items-end space-x-4 shadow-2xl z-50">
    <div 
      v-for="app in apps" 
      :key="app.id"
      class="group relative flex flex-col items-center cursor-pointer transition-all duration-300 hover:scale-110"
      @click="openApp(app.id)"
    >
      <div class="w-12 h-12 rounded-xl flex items-center justify-center text-3xl shadow-lg bg-gray-800 text-white relative overflow-hidden">
        <!-- Icon Placeholder -->
        <span v-if="!app.icon.startsWith('http')">{{ app.icon }}</span>
        <img v-else :src="app.icon" class="w-full h-full object-cover" />
      </div>
      
      <!-- Indicator for open apps -->
      <div v-if="isAppOpen(app.id)" class="w-1 h-1 bg-white rounded-full mt-1"></div>
      
      <!-- Tooltip -->
      <div class="absolute -top-10 bg-gray-800 text-white text-xs px-2 py-1 rounded opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none">
        {{ app.title }}
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { useDesktopStore } from '@/stores/desktop';

const desktopStore = useDesktopStore();

const apps = computed(() => Object.values(desktopStore.apps));

const isAppOpen = (appId: string) => {
  return desktopStore.windows.some(w => w.appId === appId);
};

const openApp = (appId: string) => {
  desktopStore.openWindow(appId);
};
</script>
