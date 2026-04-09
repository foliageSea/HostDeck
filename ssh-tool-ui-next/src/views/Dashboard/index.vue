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
  <div class="dashboard-view">
    <div class="stats-grid">
      <NCard title="CPU 使用率" :bordered="false" class="monitor-card">
        <div class="metric-value">{{ cpuUsageDisplay }}</div>
        <div class="metric-subtitle">Load: {{ cpuLoad }}</div>
        <NProgress type="line" :percentage="cpuUsagePercent" :show-indicator="false" status="success" />
      </NCard>

      <NCard title="内存" :bordered="false" class="monitor-card">
        <div class="metric-value">{{ ramUsagePercent }}%</div>
        <div class="metric-subtitle">{{ ramDetail }}</div>
        <NProgress type="line" :percentage="ramUsagePercent" :show-indicator="false" status="warning" />
      </NCard>

      <NCard title="磁盘" :bordered="false" class="monitor-card">
        <div class="metric-value">{{ diskUsage }}</div>
        <div class="metric-subtitle">根目录占用情况</div>
        <NProgress type="line" :percentage="diskUsagePercent" :show-indicator="false" status="error" />
      </NCard>

      <NCard title="网络吞吐" :bordered="false" class="monitor-card network-card">
        <div class="network-row">
          <span>上传</span>
          <strong>{{ formatSpeed(networkStats.upload) }}</strong>
        </div>
        <div class="network-row">
          <span>下载</span>
          <strong>{{ formatSpeed(networkStats.download) }}</strong>
        </div>
        <div class="metric-subtitle">数据由监控 WebSocket 实时推送</div>
      </NCard>
    </div>

    <NEmpty
      v-if="!monitorData"
      class="dashboard-empty"
      description="等待监控数据推送中..."
      size="large"
    />
  </div>
</template>

<style scoped>
.dashboard-view {
  position: relative;
  height: 100%;
  padding: 20px;
  overflow: auto;
  background: linear-gradient(180deg, rgba(15, 23, 42, 0.18), rgba(15, 23, 42, 0.06));
}

.stats-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 16px;
}

.monitor-card {
  border-radius: 18px;
  background: rgba(15, 23, 42, 0.72);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.06);
}

.metric-value {
  margin-bottom: 8px;
  font-size: 32px;
  font-weight: 700;
  line-height: 1.1;
}

.metric-subtitle {
  margin: 10px 0 14px;
  color: rgba(226, 232, 240, 0.72);
  font-size: 13px;
}

.network-card {
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}

.network-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 0;
  font-size: 15px;
  border-bottom: 1px solid rgba(148, 163, 184, 0.12);
}

.network-row:last-of-type {
  border-bottom: none;
}

.dashboard-empty {
  position: absolute;
  inset: 20px;
  border-radius: 18px;
  backdrop-filter: blur(12px);
  background: rgba(15, 23, 42, 0.4);
}

@media (max-width: 900px) {
  .stats-grid {
    grid-template-columns: 1fr;
  }
}
</style>
