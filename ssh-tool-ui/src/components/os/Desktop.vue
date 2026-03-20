<template>
  <div class="h-screen w-screen overflow-hidden relative font-sans text-gray-900 dark:text-gray-100">
    <!-- Background Layer -->
    <div class="absolute inset-0 overflow-hidden">
      <video v-if="settingsStore.backgroundType === 'video' && videoUrl" :src="videoUrl"
        class="absolute inset-0 w-full h-full object-cover" autoplay loop muted playsinline></video>
      <div v-else class="absolute inset-0 bg-cover bg-center bg-no-repeat transition-all duration-300"
        :style="{ backgroundImage: `url(${currentBgImage})` }"></div>

      <!-- Dark mode overlay -->
      <div class="absolute inset-0 bg-black/0 dark:bg-black/40 transition-colors duration-300 pointer-events-none">
      </div>
    </div>

    <!-- Top Bar -->
    <TopBar />

    <!-- Window Area -->
    <div class="absolute inset-0 top-8 bottom-20 pointer-events-none z-10">
      <div class="relative w-full h-[calc(100%-15px)] pointer-events-auto">
        <Window v-for="window in windows" :key="window.id" :window="window" />
      </div>
    </div>

    <!-- Dock -->
    <Dock />

    <!-- Window Switcher -->
    <WindowSwitcher v-if="switcherVisible" :windows="switcherWindows" :selected-index="switcherIndex"
      @select="selectWindow" />
  </div>
</template>

<script setup lang="ts">
import { computed, ref, watch, onMounted, onUnmounted } from 'vue';
import { useDesktopStore, type WindowState } from '@/stores/desktop';
import { useSettingsStore } from '@/stores/settings';
import { db } from '@/utils/db';
import TopBar from './TopBar.vue';
import Dock from './Dock.vue';
import Window from './Window.vue';
import WindowSwitcher from './WindowSwitcher.vue';
import bgImage from '@/assets/bg.jpg';

const desktopStore = useDesktopStore();
const settingsStore = useSettingsStore();

const videoUrl = ref<string>('');
const switcherVisible = ref(false);
const switcherIndex = ref(0);
const switcherWindows = ref<WindowState[]>([]);

const loadVideo = async () => {
  if (settingsStore.backgroundType === 'video') {
    try {
      const blob = await db.getVideo();
      if (blob) {
        if (videoUrl.value) URL.revokeObjectURL(videoUrl.value);
        videoUrl.value = URL.createObjectURL(blob);
      }
    } catch (error) {
      console.error('Failed to load video background:', error);
    }
  }
};

watch([() => settingsStore.backgroundType, () => settingsStore.backgroundVideoTimestamp], ([newType]) => {
  if (newType === 'video') {
    loadVideo();
  } else {
    if (videoUrl.value) {
      URL.revokeObjectURL(videoUrl.value);
      videoUrl.value = '';
    }
  }
});

const selectWindow = (index: number) => {
  const targetWindow = switcherWindows.value[index];
  if (targetWindow) {
    desktopStore.focusWindow(targetWindow.id);
  }
  switcherVisible.value = false;
};

const handleKeyDown = (e: KeyboardEvent) => {
  if (e.key === 'Escape' && switcherVisible.value) {
    switcherVisible.value = false;
    return;
  }

  const isSwitchKey = (e.ctrlKey && e.key === 'Tab') || (e.altKey && (e.key === 'q' || e.key === '`'));

  if (isSwitchKey) {
    e.preventDefault();
    e.stopPropagation();

    if (!switcherVisible.value) {
      // Open switcher
      // Sort windows by zIndex descending (most recent first)
      const sorted = [...desktopStore.windows].sort((a, b) => b.zIndex - a.zIndex);
      if (sorted.length < 2) return;

      switcherWindows.value = sorted;
      switcherVisible.value = true;
      // Select the previous window (index 1) by default, or last if shift is held
      switcherIndex.value = e.shiftKey ? sorted.length - 1 : 1;
    } else {
      // Cycle selection
      if (e.shiftKey) {
        switcherIndex.value = (switcherIndex.value - 1 + switcherWindows.value.length) % switcherWindows.value.length;
      } else {
        switcherIndex.value = (switcherIndex.value + 1) % switcherWindows.value.length;
      }
    }
  }
};

const handleKeyUp = (e: KeyboardEvent) => {
  if (e.key === 'Control' || e.key === 'Alt') {
    if (switcherVisible.value) {
      selectWindow(switcherIndex.value);
    }
  }
};

onMounted(() => {
  loadVideo();
  window.addEventListener('keydown', handleKeyDown, true);
  window.addEventListener('keyup', handleKeyUp, true);
});

onUnmounted(() => {
  if (videoUrl.value) URL.revokeObjectURL(videoUrl.value);
  window.removeEventListener('keydown', handleKeyDown, true);
  window.removeEventListener('keyup', handleKeyUp, true);
});

const windows = computed(() => desktopStore.windows);
const currentBgImage = computed(() => settingsStore.customBackground || bgImage);
</script>
