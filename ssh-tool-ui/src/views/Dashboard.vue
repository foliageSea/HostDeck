<template>
  <div class="h-full bg-background p-4 overflow-auto flex justify-center items-start">
    <div class="flex flex-col gap-4 w-full max-w-md">
      <!-- CPU Card -->
      <Card>
        <CardHeader class="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle class="text-sm font-medium">CPU 使用率</CardTitle>
          <Cpu class="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <div class="text-2xl font-bold">{{ cpuUsageDisplay }}</div>
          <p class="text-xs text-muted-foreground mb-4">Load: {{ cpuLoad }}</p>
          <Progress :model-value="cpuUsagePercent" class="h-2" />
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
          <Progress :model-value="diskUsagePercent" class="mt-4 h-2" />
        </CardContent>
      </Card>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { useSshStore } from '../stores/ssh';
import { Cpu, MemoryStick, HardDrive } from 'lucide-vue-next';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Progress } from '@/components/ui/progress'

const props = defineProps<{
  windowId?: string
}>();

const sshStore = useSshStore();

const monitorData = computed(() => sshStore.monitorData);

const cpuLoad = computed(() => monitorData.value?.cpu || '0.0');

const cpuUsagePercent = computed(() => {
  if (monitorData.value?.cpuUsage !== undefined) {
    return monitorData.value.cpuUsage;
  }
  return 0;
});

const cpuUsageDisplay = computed(() => {
  return `${cpuUsagePercent.value.toFixed(1)}%`;
});

const ramUsage = computed(() => {
  const data = monitorData.value;
  if (!data || !data.ram) return 0;
  const total = data.ram.total || 0;
  const used = data.ram.used || 0;
  return total > 0 ? Math.round((used / total) * 100) : 0;
});

const ramDetails = computed(() => {
  const data = monitorData.value;
  if (!data || !data.ram) return '0 / 0 MB';
  return `${data.ram.used || 0} / ${data.ram.total || 0} MB`;
});

const diskUsage = computed(() => monitorData.value?.disk || '0%');
const diskUsagePercent = computed(() => parseFloat(diskUsage.value) || 0);

</script>
