<template>
  <div v-if="sshStore.isConnected" class="flex items-center space-x-4 text-xs font-medium">
    <div class="flex items-center space-x-2" title="CPU Usage">
      <Cpu class="w-3.5 h-3.5" />
      <span>{{ cpuDisplay }}</span>
    </div>
    <div class="flex items-center space-x-2" title="Memory Usage">
      <MemoryStick class="w-3.5 h-3.5" />
      <span>{{ ramDisplay }}</span>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue';
import { useSshStore } from '../../stores/ssh';
import { Cpu, MemoryStick } from 'lucide-vue-next';

const sshStore = useSshStore();
const cpuUsage = ref<number | null>(null);
const cpuLoad = ref('0.0');
const ramUsage = ref(0);
let interval: any = null;

const cpuDisplay = computed(() => {
  if (cpuUsage.value !== null) {
    return `${cpuUsage.value.toFixed(1)}%`;
  }
  return `Load: ${cpuLoad.value}`;
});

const ramDisplay = computed(() => {
  return `${ramUsage.value}%`;
});

async function fetchData() {
  if (!sshStore.sessionId) return;
  try {
    const res = await fetch(`/api/monitor?sessionId=${sshStore.sessionId}`);
    if (res.ok) {
      const data = await res.json();
      
      // CPU
      if (typeof data.cpuUsage === 'number') {
        cpuUsage.value = data.cpuUsage;
      } else {
        cpuUsage.value = null;
      }
      cpuLoad.value = data.cpu;
      
      // RAM
      const total = data.ram.total;
      const used = data.ram.used;
      ramUsage.value = total > 0 ? Math.round((used / total) * 100) : 0;
    }
  } catch (e) {
    console.error('Failed to fetch system status', e);
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
