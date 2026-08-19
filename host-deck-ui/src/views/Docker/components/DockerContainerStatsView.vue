<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { LineChart } from 'echarts/charts'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import { use } from 'echarts/core'
import type { EChartsOption } from 'echarts'
import { CanvasRenderer } from 'echarts/renderers'
import VChart from 'vue-echarts'
import { dockerApi, type DockerContainerStatsSample } from '@/api/docker'
import { useSettingsStore } from '@/stores/settings'

use([CanvasRenderer, GridComponent, LegendComponent, LineChart, TooltipComponent])
const props = defineProps<{ connectionId: string; containerId: string; containerName: string }>()
const settingsStore = useSettingsStore()
const samples = ref<DockerContainerStatsSample[]>([])
const status = ref<'connecting' | 'live' | 'ended' | 'error'>('connecting')
const error = ref('')
let abortController: AbortController | null = null
let generation = 0
const currentSample = computed(() => samples.value.at(-1))

function formatPercent(value: number | string) {
  const numericValue = Number(value)
  return `${(Number.isFinite(numericValue) ? numericValue : 0).toFixed(1)}%`
}
function formatBytes(value: number | string) {
  const numericValue = Number(value)
  if (!Number.isFinite(numericValue) || numericValue <= 0) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const index = Math.max(
    0,
    Math.min(Math.floor(Math.log(numericValue) / Math.log(1024)), units.length - 1),
  )
  const size = numericValue / 1024 ** index
  return `${size.toFixed(size >= 10 || index === 0 ? 0 : 1)} ${units[index]}`
}
function createOption(
  series: Array<{ name: string; color: string; data: number[] }>,
  formatter: (value: number | string) => string,
  max?: number,
): EChartsOption {
  const axisColor = settingsStore.isDark ? 'rgba(148,163,184,0.72)' : 'rgba(71,85,105,0.72)'
  return {
    animation: false,
    grid: { left: 12, right: 16, top: 18, bottom: 8, containLabel: true },
    tooltip: { trigger: 'axis', valueFormatter: (value) => formatter(Number(value)) },
    xAxis: {
      type: 'category',
      boundaryGap: false,
      data: samples.value.map((sample) =>
        new Date(sample.timestamp).toLocaleTimeString('zh-CN', { hour12: false }),
      ),
      axisLabel: { color: axisColor, hideOverlap: true },
    },
    yAxis: {
      type: 'value',
      min: 0,
      max,
      axisLabel: { color: axisColor, formatter },
      splitLine: { show: false },
    },
    series: series.map((item) => ({
      name: item.name,
      type: 'line',
      data: item.data,
      showSymbol: false,
      smooth: true,
      lineStyle: { color: item.color, width: 2 },
      areaStyle: { color: `${item.color}1f` },
    })),
  }
}
const cpuOption = computed(() =>
  createOption(
    [{ name: 'CPU', color: '#0ea5e9', data: samples.value.map((sample) => sample.cpuPercent) }],
    formatPercent,
  ),
)
const memoryOption = computed(() =>
  createOption(
    [{ name: '内存', color: '#f43f5e', data: samples.value.map((sample) => sample.memoryPercent) }],
    formatPercent,
    100,
  ),
)
const networkOption = computed(() =>
  createOption(
    [
      {
        name: '接收',
        color: '#10b981',
        data: samples.value.map((sample) => sample.networkRxBytesPerSecond),
      },
      {
        name: '发送',
        color: '#f59e0b',
        data: samples.value.map((sample) => sample.networkTxBytesPerSecond),
      },
    ],
    (value) => `${formatBytes(value)}/s`,
  ),
)
function stopStream() {
  generation += 1
  abortController?.abort()
  abortController = null
}
async function refreshStats() {
  stopStream()
  const currentGeneration = generation
  const controller = new AbortController()
  abortController = controller
  samples.value = []
  error.value = ''
  status.value = 'connecting'
  try {
    await dockerApi.streamContainerStats(
      props.connectionId,
      props.containerId,
      (event) => {
        if (currentGeneration !== generation) return
        if (event.event === 'stats') {
          status.value = 'live'
          const cutoff = event.data.timestamp - 5 * 60 * 1000
          samples.value = [...samples.value, event.data]
            .filter((sample) => sample.timestamp >= cutoff)
            .slice(-300)
        } else if (event.event === 'connected') status.value = 'live'
        else if (event.event === 'done') status.value = 'ended'
      },
      controller.signal,
    )
  } catch (caughtError) {
    if (!controller.signal.aborted && currentGeneration === generation) {
      status.value = 'error'
      error.value = caughtError instanceof Error ? caughtError.message : '容器资源监控失败。'
    }
  }
}
onMounted(() => void refreshStats())
onBeforeUnmount(stopStream)
</script>

<template>
  <div class="flex h-full min-h-0 flex-col gap-[12px] p-[16px]">
    <div class="flex items-center justify-between">
      <NTag size="small" round :type="status === 'error' ? 'error' : 'success'">{{
        status === 'connecting'
          ? '连接中'
          : status === 'live'
            ? '实时'
            : status === 'ended'
              ? '已结束'
              : '已断开'
      }}</NTag
      ><NButton size="small" quaternary @click="refreshStats">重新连接</NButton>
    </div>
    <NAlert v-if="error" type="error" :show-icon="true">{{ error }}</NAlert>
    <div class="grid grid-cols-4 gap-[8px] lt-md:grid-cols-2">
      <NCard size="small"
        >CPU<br /><strong>{{ formatPercent(currentSample?.cpuPercent ?? 0) }}</strong></NCard
      ><NCard size="small"
        >内存<br /><strong>{{ formatPercent(currentSample?.memoryPercent ?? 0) }}</strong></NCard
      ><NCard size="small"
        >网络接收<br /><strong
          >{{ formatBytes(currentSample?.networkRxBytesPerSecond ?? 0) }}/s</strong
        ></NCard
      ><NCard size="small"
        >网络发送<br /><strong
          >{{ formatBytes(currentSample?.networkTxBytesPerSecond ?? 0) }}/s</strong
        ></NCard
      >
    </div>
    <NSpin :show="status === 'connecting' && !samples.length" class="min-h-0 flex-1"
      ><div class="grid h-full grid-cols-2 gap-[10px] lt-md:grid-cols-1">
        <NCard size="small"
          ><template #header>CPU 使用率</template
          ><VChart :option="cpuOption" :autoresize="true" class="h-[220px]" /></NCard
        ><NCard size="small"
          ><template #header>内存使用率</template
          ><VChart :option="memoryOption" :autoresize="true" class="h-[220px]" /></NCard
        ><NCard size="small" class="col-span-2 lt-md:col-span-1"
          ><template #header>网络吞吐</template
          ><VChart :option="networkOption" :autoresize="true" class="h-[220px]"
        /></NCard></div
    ></NSpin>
  </div>
</template>
