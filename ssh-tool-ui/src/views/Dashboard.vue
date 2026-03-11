<template>
  <div class="h-full bg-gray-100 p-4 overflow-auto">
    <div class="grid grid-cols-1 gap-4">
      <!-- CPU Card -->
      <div class="bg-white p-4 rounded-xl shadow-sm border border-gray-200">
        <div class="flex items-center justify-between mb-2">
          <h3 class="text-xs font-bold text-gray-500 uppercase tracking-wider">CPU Load</h3>
          <span class="text-2xl">🧠</span>
        </div>
        <div class="text-2xl font-bold text-gray-800">{{ cpuLoad }}</div>
        <div class="w-full bg-gray-200 rounded-full h-1.5 mt-2">
          <div class="bg-blue-500 h-1.5 rounded-full transition-all duration-500" :style="{ width: `${Math.min(parseFloat(cpuLoad) * 10, 100)}%` }"></div>
        </div>
      </div>
      
      <!-- RAM Card -->
      <div class="bg-white p-4 rounded-xl shadow-sm border border-gray-200">
        <div class="flex items-center justify-between mb-2">
          <h3 class="text-xs font-bold text-gray-500 uppercase tracking-wider">Memory</h3>
          <span class="text-2xl">💾</span>
        </div>
        <div class="text-2xl font-bold text-gray-800">{{ ramUsage }}%</div>
        <div class="text-xs text-gray-400 mt-1">{{ ramDetails }}</div>
        <div class="w-full bg-gray-200 rounded-full h-1.5 mt-2">
          <div class="bg-green-500 h-1.5 rounded-full transition-all duration-500" :style="{ width: `${ramUsage}%` }"></div>
        </div>
      </div>
      
      <!-- Disk Card -->
      <div class="bg-white p-4 rounded-xl shadow-sm border border-gray-200">
        <div class="flex items-center justify-between mb-2">
          <h3 class="text-xs font-bold text-gray-500 uppercase tracking-wider">Disk (Root)</h3>
          <span class="text-2xl">💿</span>
        </div>
        <div class="text-2xl font-bold text-gray-800">{{ diskUsage }}</div>
        <div class="w-full bg-gray-200 rounded-full h-1.5 mt-2">
          <div class="bg-purple-500 h-1.5 rounded-full transition-all duration-500" :style="{ width: diskUsage }"></div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';
import { useSshStore } from '../stores/ssh';

const props = defineProps<{
  windowId?: string
}>();

const sshStore = useSshStore();
const cpuLoad = ref('0.0');
const ramUsage = ref(0);
const ramDetails = ref('0 / 0 MB');
const diskUsage = ref('0%');
let interval: any = null;

async function fetchData() {
  if (!sshStore.sessionId) return;
  try {
    const res = await fetch(`/api/monitor?sessionId=${sshStore.sessionId}`);
    if (res.ok) {
      const data = await res.json();
      cpuLoad.value = data.cpu;
      diskUsage.value = data.disk;
      
      const total = data.ram.total;
      const used = data.ram.used;
      ramUsage.value = total > 0 ? Math.round((used / total) * 100) : 0;
      ramDetails.value = `${used} / ${total} MB`;
    }
  } catch (e) {
    console.error(e);
  }
}

onMounted(() => {
  if (sshStore.isConnected) {
    fetchData();
    interval = setInterval(fetchData, 3000);
  }
});

onUnmounted(() => {
  if (interval) clearInterval(interval);
});
</script>
