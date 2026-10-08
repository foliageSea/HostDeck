<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { ArrowDown, ArrowUp, HardDrive } from '@lucide/vue'
import { systemApi, type MonitorResponse } from '@/api/system'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'
import WidgetSparkline from './WidgetSparkline.vue'

const sampleLimit = 20
const sshStore = useSshStore()
const settingsStore = useSettingsStore()
const samples = ref<MonitorResponse[]>([])
const historyLoading = ref(false)
let historyRequestId = 0

const currentSample = computed(
  () => sshStore.monitorData ?? samples.value[samples.value.length - 1] ?? null,
)
const cpuPercent = computed(() => currentSample.value?.cpuUsage ?? null)
const memoryPercent = computed(() => {
  const ram = currentSample.value?.ram
  return ram?.total ? (ram.used / ram.total) * 100 : null
})
const diskPercent = computed(() => {
  const disk = currentSample.value?.disk.trim() ?? ''
  return /^\d+(\.\d+)?%$/.test(disk) ? Number.parseFloat(disk) : null
})
const cpuSeries = computed(() => samples.value.map((sample) => sample.cpuUsage ?? 0))
const memorySeries = computed(() =>
  samples.value.map((sample) =>
    sample.ram.total ? (sample.ram.used / sample.ram.total) * 100 : 0,
  ),
)
const hostName = computed(
  () => currentSample.value?.systemInfo?.hostname || sshStore.host || '当前主机',
)
const statusText = computed(() => {
  if (sshStore.monitorError) return '采样异常'
  if (!currentSample.value) return historyLoading.value ? '载入历史数据' : '等待采样'
  return `更新于 ${formatTime(currentSample.value.timestamp)}`
})

watch(
  () => sshStore.monitorData,
  (sample) => {
    if (sample) mergeSamples([sample])
  },
  { immediate: true },
)

watch(
  () => sshStore.connectionId,
  async (connectionId) => {
    const requestId = ++historyRequestId
    samples.value = []
    if (!connectionId) return

    historyLoading.value = true
    try {
      const history = await systemApi.getMonitorHistory(connectionId, sampleLimit)
      if (requestId === historyRequestId) {
        mergeSamples(sshStore.monitorData ? [...history, sshStore.monitorData] : history)
      }
    } catch (error) {
      console.error('Failed to load widget monitor history', error)
    } finally {
      if (requestId === historyRequestId) historyLoading.value = false
    }
  },
  { immediate: true },
)

function mergeSamples(items: MonitorResponse[]) {
  const uniqueSamples = new Map<number, MonitorResponse>()
  for (const sample of [...samples.value, ...items]) {
    uniqueSamples.set(sample.timestamp, sample)
  }
  samples.value = [...uniqueSamples.values()]
    .sort((left, right) => left.timestamp - right.timestamp)
    .slice(-sampleLimit)
}

function formatPercent(value: number | null) {
  return value === null ? '--' : `${value.toFixed(1)}%`
}

function formatSpeed(value: number | undefined) {
  const speed = value ?? 0
  if (speed >= 1024 * 1024) return `${(speed / 1024 / 1024).toFixed(2)} MB/s`
  if (speed >= 1024) return `${(speed / 1024).toFixed(1)} KB/s`
  return `${speed.toFixed(0)} B/s`
}

function formatTime(timestamp: number) {
  return new Intl.DateTimeFormat('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).format(new Date(timestamp))
}
</script>

<template>
  <div class="performance-widget" :class="{ 'performance-widget--dark': settingsStore.isDark }">
    <div class="performance-widget__host">
      <div class="min-w-0">
        <div class="truncate text-[13px] font-700">{{ hostName }}</div>
        <div class="mt-[2px] text-[10px] opacity-60">{{ statusText }}</div>
      </div>
      <span
        class="h-[8px] w-[8px] shrink-0 rounded-full"
        :class="
          sshStore.monitorError ? 'bg-[#fb7185]' : currentSample ? 'bg-[#34d399]' : 'bg-[#94a3b8]'
        "
      />
    </div>

    <div class="performance-widget__charts">
      <div class="performance-widget__chart">
        <div class="performance-widget__chart-meta">
          <span>CPU</span>
          <strong>{{ formatPercent(cpuPercent) }}</strong>
        </div>
        <WidgetSparkline color="#38bdf8" :values="cpuSeries" />
      </div>
      <div class="performance-widget__chart">
        <div class="performance-widget__chart-meta">
          <span>内存</span>
          <strong>{{ formatPercent(memoryPercent) }}</strong>
        </div>
        <WidgetSparkline color="#fb7185" :values="memorySeries" />
      </div>
    </div>

    <div class="performance-widget__stats">
      <div class="performance-widget__stat">
        <HardDrive :size="15" aria-hidden="true" />
        <span>磁盘</span>
        <strong>{{ formatPercent(diskPercent) }}</strong>
      </div>
      <div class="performance-widget__stat">
        <ArrowUp :size="15" aria-hidden="true" />
        <span>上传</span>
        <strong>{{ formatSpeed(currentSample?.network?.uploadSpeed) }}</strong>
      </div>
      <div class="performance-widget__stat">
        <ArrowDown :size="15" aria-hidden="true" />
        <span>下载</span>
        <strong>{{ formatSpeed(currentSample?.network?.downloadSpeed) }}</strong>
      </div>
    </div>
  </div>
</template>

<style scoped>
.performance-widget {
  height: 100%;
  padding: 0 14px 14px;
  color: #0f172a;
}
.performance-widget--dark {
  color: #e2e8f0;
}
.performance-widget__host {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 9px 2px 11px;
  border-bottom: 1px solid rgba(148, 163, 184, 0.18);
}
.performance-widget__charts {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
  margin-top: 12px;
}
.performance-widget__chart {
  height: 104px;
  padding: 10px;
  border: 1px solid rgba(148, 163, 184, 0.16);
  border-radius: var(--app-radius-item);
  background: rgba(255, 255, 255, 0.36);
}
.performance-widget--dark .performance-widget__chart {
  background: rgba(15, 23, 42, 0.28);
}
.performance-widget__chart-meta {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 5px;
  font-size: 11px;
}
.performance-widget__chart-meta span {
  opacity: 0.64;
}
.performance-widget__chart-meta strong {
  font-size: 16px;
  font-variant-numeric: tabular-nums;
}
.performance-widget__chart svg {
  height: 52px;
}
.performance-widget__stats {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 8px;
  margin-top: 10px;
}
.performance-widget__stat {
  display: grid;
  grid-template-columns: auto 1fr;
  align-items: center;
  gap: 2px 6px;
  min-width: 0;
  padding: 9px;
  border-radius: var(--app-radius-item);
  background: rgba(148, 163, 184, 0.1);
  font-size: 10px;
}
.performance-widget__stat svg {
  grid-row: span 2;
  color: var(--app-primary-color);
}
.performance-widget__stat span {
  opacity: 0.62;
}
.performance-widget__stat strong {
  min-width: 0;
  overflow: hidden;
  font-size: 11px;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-variant-numeric: tabular-nums;
}
</style>
