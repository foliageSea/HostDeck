<template>
  <div class="h-screen w-screen overflow-hidden bg-cover bg-center bg-no-repeat relative font-sans text-gray-900" 
       style="background-image: url('https://images.unsplash.com/photo-1494548162494-384bba4ab999?ixlib=rb-1.2.1&auto=format&fit=crop&w=1920&q=80')">
    
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
import TopBar from './TopBar.vue';
import Dock from './Dock.vue';
import Window from './Window.vue';

const desktopStore = useDesktopStore();
const windows = computed(() => desktopStore.windows);
</script>
