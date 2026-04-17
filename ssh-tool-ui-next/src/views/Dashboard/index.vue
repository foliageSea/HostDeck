<script setup lang="ts">
import { computed } from 'vue'
import { useSshStore } from '@/stores/ssh'

const sshStore = useSshStore()

const monitorData = computed(() => sshStore.monitorData)

const cpuLoad = computed(() => monitorData.value?.cpu || '0.0')

const cpuUsagePercent = computed(() => {
  if (typeof monitorData.value?.cpuUsage === 'number') {
    return monitorData.value.cpuUsage
  }

  return 0
})

const cpuUsageDisplay = computed(() => `${cpuUsagePercent.value.toFixed(1)}%`)

const ramUsagePercent = computed(() => {
  const ram = monitorData.value?.ram
  if (!ram?.total) {
    return 0
  }

  return Math.round((ram.used / ram.total) * 100)
})

const ramDetail = computed(() => {
  const ram = monitorData.value?.ram
  if (!ram) {
    return '0 / 0 MB'
  }

  return `${ram.used || 0} / ${ram.total || 0} MB`
})

const diskUsage = computed(() => monitorData.value?.disk || '0%')
const diskUsagePercent = computed(() => Number.parseFloat(diskUsage.value) || 0)

const networkStats = computed(() => {
  const network = monitorData.value?.network
  return {
    download: network?.downloadSpeed ?? 0,
    upload: network?.uploadSpeed ?? 0,
  }
})

function formatSpeed(value: number) {
  if (value >= 1024 * 1024) {
    return `${(value / 1024 / 1024).toFixed(2)} MB/s`
  }

  if (value >= 1024) {
    return `${(value / 1024).toFixed(1)} KB/s`
  }

  return `${value.toFixed(0)} B/s`
}
</script>

<template>
  <div class="relative h-full overflow-auto bg-[linear-gradient(180deg,rgba(15,23,42,0.18),rgba(15,23,42,0.06))] p-[20px]">
    <div class="stats-grid grid grid-cols-[repeat(2,minmax(0,1fr))] gap-[16px]">
      <NCard title="CPU 使用率" :bordered="false" class="rounded-[18px] bg-[rgba(15,23,42,0.72)] shadow-[inset_0_1px_0_rgba(255,255,255,0.06)]">
        <div class="mb-[8px] text-[32px] font-700 leading-[1.1]">{{ cpuUsageDisplay }}</div>
        <div class="my-[10px] mb-[14px] text-[13px] text-[rgba(226,232,240,0.72)]">Load: {{ cpuLoad }}</div>
        <NProgress type="line" :percentage="cpuUsagePercent" :show-indicator="false" status="success" />
      </NCard>

      <NCard title="内存" :bordered="false" class="rounded-[18px] bg-[rgba(15,23,42,0.72)] shadow-[inset_0_1px_0_rgba(255,255,255,0.06)]">
        <div class="mb-[8px] text-[32px] font-700 leading-[1.1]">{{ ramUsagePercent }}%</div>
        <div class="my-[10px] mb-[14px] text-[13px] text-[rgba(226,232,240,0.72)]">{{ ramDetail }}</div>
        <NProgress type="line" :percentage="ramUsagePercent" :show-indicator="false" status="warning" />
      </NCard>

      <NCard title="磁盘" :bordered="false" class="rounded-[18px] bg-[rgba(15,23,42,0.72)] shadow-[inset_0_1px_0_rgba(255,255,255,0.06)]">
        <div class="mb-[8px] text-[32px] font-700 leading-[1.1]">{{ diskUsage }}</div>
        <div class="my-[10px] mb-[14px] text-[13px] text-[rgba(226,232,240,0.72)]">根目录占用情况</div>
        <NProgress type="line" :percentage="diskUsagePercent" :show-indicator="false" status="error" />
      </NCard>

      <NCard title="网络吞吐" :bordered="false" class="flex flex-col justify-between rounded-[18px] bg-[rgba(15,23,42,0.72)] shadow-[inset_0_1px_0_rgba(255,255,255,0.06)]">
        <div class="flex items-center justify-between border-b-0 border-[rgba(148,163,184,0.12)] py-[10px] text-[15px]">
          <span>上传</span>
          <strong>{{ formatSpeed(networkStats.upload) }}</strong>
        </div>
        <div class="flex items-center justify-between border-b border-[rgba(148,163,184,0.12)] py-[10px] text-[15px] last:border-b-0">
          <span>下载</span>
          <strong>{{ formatSpeed(networkStats.download) }}</strong>
        </div>
        <div class="my-[10px] mb-[14px] text-[13px] text-[rgba(226,232,240,0.72)]">数据由监控 WebSocket 实时推送</div>
      </NCard>
    </div>

    <NEmpty
      v-if="!monitorData"
      class="absolute inset-[20px] rounded-[18px] bg-[rgba(15,23,42,0.4)] backdrop-blur-[12px]"
      description="等待监控数据推送中..."
      size="large"
    />
  </div>
</template>

<style scoped>
@media (max-width: 900px) {
  .stats-grid {
    grid-template-columns: 1fr;
  }
}
</style>
