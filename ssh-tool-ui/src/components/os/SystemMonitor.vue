<template>
  <div v-if="sshStore.isConnected" class="flex items-center space-x-4 text-xs font-medium">
    <div class="flex items-center space-x-2" title="Upload Speed">
      <ArrowUp class="w-3.5 h-3.5 text-blue-400" />
      <span>{{ formatSpeed(uploadSpeed) }}</span>
    </div>
    <div class="flex items-center space-x-2" title="Download Speed">
      <ArrowDown class="w-3.5 h-3.5 text-green-400" />
      <span>{{ formatSpeed(downloadSpeed) }}</span>
    </div>
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
import { computed } from 'vue';
import { useSshStore } from '../../stores/ssh';
import { Cpu, MemoryStick, ArrowUp, ArrowDown } from 'lucide-vue-next';
import { useQuery } from '@tanstack/vue-query';
import { systemApi } from '@/api/system';

const sshStore = useSshStore();

const { data: monitorData } = useQuery({
  queryKey: computed(() => ['monitor', sshStore.sessionId]),
  queryFn: () => systemApi.getMonitorStatus(sshStore.sessionId!),
  enabled: computed(() => !!sshStore.sessionId && sshStore.isConnected),
  refetchInterval: 3000
});

const cpuDisplay = computed(() => {
  const data = monitorData.value;
  if (!data) return '0.0%';
  
  if (data.cpuUsage !== undefined && data.cpuUsage !== null) {
    return `${data.cpuUsage.toFixed(1)}%`;
  }
  return `Load: ${data.cpu || '0.0'}`;
});

const ramDisplay = computed(() => {
  const data = monitorData.value;
  if (!data) return '0%';
  
  const total = data.ram.total;
  const used = data.ram.used;
  const percentage = total > 0 ? Math.round((used / total) * 100) : 0;
  return `${percentage}%`;
});

const uploadSpeed = computed(() => monitorData.value?.network?.uploadSpeed || 0);
const downloadSpeed = computed(() => monitorData.value?.network?.downloadSpeed || 0);

function formatSpeed(bytes: number) {
  if (bytes === 0) return '0 B/s';
  const k = 1024;
  const sizes = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}
</script>
