<template>
  <div class="fixed top-0 left-0 right-0 h-8 bg-gray-800/80 backdrop-blur-md text-white flex items-center justify-between px-4 z-50 shadow-sm select-none">
    <div class="flex items-center space-x-4">
      <span class="font-bold text-sm"></span>
      <span class="text-sm font-semibold">SSH Tool</span>
      <span class="text-sm hover:bg-white/10 px-2 py-0.5 rounded cursor-pointer">File</span>
      <span class="text-sm hover:bg-white/10 px-2 py-0.5 rounded cursor-pointer">Edit</span>
      <span class="text-sm hover:bg-white/10 px-2 py-0.5 rounded cursor-pointer">View</span>
      <span class="text-sm hover:bg-white/10 px-2 py-0.5 rounded cursor-pointer">Window</span>
      <span class="text-sm hover:bg-white/10 px-2 py-0.5 rounded cursor-pointer">Help</span>
    </div>
    <div class="flex items-center space-x-4">
      <span class="text-sm">{{ currentTime }}</span>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';

const currentTime = ref('');

const updateTime = () => {
  const now = new Date();
  currentTime.value = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
};

let interval: number;

onMounted(() => {
  updateTime();
  interval = setInterval(updateTime, 1000);
});

onUnmounted(() => {
  clearInterval(interval);
});
</script>
