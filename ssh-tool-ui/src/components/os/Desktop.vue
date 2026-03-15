<template>
  <div class="h-screen w-screen overflow-hidden relative font-sans text-gray-900 dark:text-gray-100">
    <!-- Background Layer -->
    <div 
      class="absolute inset-0 bg-cover bg-center bg-no-repeat transition-all duration-300"
      :style="{ backgroundImage: `url(${currentBgImage})` }"
    >
      <!-- Dark mode overlay -->
      <div class="absolute inset-0 bg-black/0 dark:bg-black/40 transition-colors duration-300"></div>
    </div>
    
    <!-- Top Bar -->
    <TopBar />
    
    <!-- Window Area -->
    <div class="absolute inset-0 top-8 bottom-20 pointer-events-none">
      <div class="relative w-full h-full pointer-events-auto">
        <Window 
          v-for="window in windows" 
          :key="window.id" 
          :window="window" 
        />
      </div>
    </div>
    
    <!-- Dock -->
    <Dock />
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { useDesktopStore } from '@/stores/desktop';
import { useSettingsStore } from '@/stores/settings';
import TopBar from './TopBar.vue';
import Dock from './Dock.vue';
import Window from './Window.vue';
import bgImage from '@/assets/bg.jpg';

const desktopStore = useDesktopStore();
const settingsStore = useSettingsStore();

const windows = computed(() => desktopStore.windows);
const currentBgImage = computed(() => settingsStore.customBackground || bgImage);
</script>
