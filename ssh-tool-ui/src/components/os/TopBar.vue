<template>
  <div class="fixed top-0 left-0 right-0 h-8 bg-gray-800/80 backdrop-blur-md text-white flex items-center justify-between px-4 z-50 shadow-sm select-none">
    <div class="flex items-center space-x-4">
      <span class="font-bold text-sm flex items-center"><Terminal class="w-4 h-4 mr-2"/> SSH Tool</span>
      <span class="text-sm hover:bg-white/10 px-2 py-0.5 rounded cursor-pointer">文件</span>
      <span class="text-sm hover:bg-white/10 px-2 py-0.5 rounded cursor-pointer">编辑</span>
      <span class="text-sm hover:bg-white/10 px-2 py-0.5 rounded cursor-pointer">视图</span>
      <span class="text-sm hover:bg-white/10 px-2 py-0.5 rounded cursor-pointer">窗口</span>
      <span class="text-sm hover:bg-white/10 px-2 py-0.5 rounded cursor-pointer">帮助</span>
    </div>
    <div class="flex items-center space-x-4">
      <span class="text-sm">{{ currentTime }}</span>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';
import { Terminal } from 'lucide-vue-next';

const currentTime = ref('');

const updateTime = () => {
  const now = new Date();
  currentTime.value = now.toLocaleTimeString('zh-CN', { 
    hour: 'numeric', 
    minute: '2-digit',
    hour12: true 
  });
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
