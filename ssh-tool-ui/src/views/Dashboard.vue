<template>
  <div class="h-full bg-background p-4 overflow-auto">
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      <!-- CPU Card -->
      <Card>
        <CardHeader class="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle class="text-sm font-medium">CPU 负载</CardTitle>
          <Cpu class="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <div class="text-2xl font-bold">{{ cpuLoad }}</div>
          <Progress :model-value="parseFloat(cpuLoad) * 10" class="mt-4 h-2" />
        </CardContent>
      </Card>
      
      <!-- RAM Card -->
      <Card>
        <CardHeader class="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle class="text-sm font-medium">内存</CardTitle>
          <MemoryStick class="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <div class="text-2xl font-bold">{{ ramUsage }}%</div>
          <p class="text-xs text-muted-foreground mb-4">{{ ramDetails }}</p>
          <Progress :model-value="ramUsage" class="h-2" />
        </CardContent>
      </Card>
      
      <!-- Disk Card -->
      <Card>
        <CardHeader class="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle class="text-sm font-medium">磁盘 (根目录)</CardTitle>
          <HardDrive class="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <div class="text-2xl font-bold">{{ diskUsage }}</div>
          <Progress :model-value="parseFloat(diskUsage)" class="mt-4 h-2" />
        </CardContent>
      </Card>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue';
import { useSshStore } from '../stores/ssh';
import { Cpu, MemoryStick, HardDrive } from 'lucide-vue-next';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Progress } from '@/components/ui/progress'

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