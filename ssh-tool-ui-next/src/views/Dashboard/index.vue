<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { LineChart } from 'echarts/charts'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import { use } from 'echarts/core'
import type { EChartsOption } from 'echarts'
import { CanvasRenderer } from 'echarts/renderers'
import VChart from 'vue-echarts'
import { systemApi, type MonitorResponse } from '@/api/system'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'

use([CanvasRenderer, GridComponent, LegendComponent, LineChart, TooltipComponent])

type RangeKey = '1m' | '5m' | '10m'

const sshStore = useSshStore()
const settingsStore = useSettingsStore()

const historyLimit = 200
const rangeOptions: Array<{ key: RangeKey, label: string }> = [
  { key: '1m', label: '1 分钟' },
  { key: '5m', label: '5 分钟' },
  { key: '10m', label: '10 分钟' },
]
const historyLoading = ref(true)
const historyError = ref<string | null>(null)
const selectedRange = ref<RangeKey>('5m')
const smoothLines = ref(true)
const samples = ref<MonitorResponse[]>([])

const monitorError = computed(() => sshStore.monitorError)
const currentSample = computed(() => sshStore.monitorData ?? samples.value[samples.value.length - 1] ?? null)
const hasSamples = computed(() => samples.value.length > 0)
const lastUpdatedAt = computed(() => currentSample.value?.timestamp ?? null)

const cpuLoad = computed(() => currentSample.value?.cpu || '0.0')
const cpuUsagePercent = computed(() => currentSample.value?.cpuUsage ?? 0)
const cpuUsageDisplay = computed(() => `${cpuUsagePercent.value.toFixed(1)}%`)

const ramUsagePercent = computed(() => {
  const ram = currentSample.value?.ram
  if (!ram?.total) {
    return 0
  }

  return (ram.used / ram.total) * 100
})

const ramUsageDisplay = computed(() => `${ramUsagePercent.value.toFixed(1)}%`)
const ramDetail = computed(() => {
  const ram = currentSample.value?.ram
  if (!ram) {
    return '--'
  }

  return `${formatMemory(ram.used)} / ${formatMemory(ram.total)}`
})

const diskUsage = computed(() => currentSample.value?.disk || '--')
const uploadSpeed = computed(() => currentSample.value?.network?.uploadSpeed ?? 0)
const downloadSpeed = computed(() => currentSample.value?.network?.downloadSpeed ?? 0)
const latestUpdateText = computed(() => {
  if (!lastUpdatedAt.value) {
    return '等待采样中'
  }

  return formatFullTime(lastUpdatedAt.value)
})

const visibleSamples = computed(() => samples.value.slice(-getRangeLimit(selectedRange.value)))
const visibleRangeLabel = computed(() => rangeOptions.find((option) => option.key === selectedRange.value)?.label ?? '5 分钟')
const chartTimestamps = computed(() => visibleSamples.value.map((sample) => sample.timestamp))
const cpuSeries = computed(() => visibleSamples.value.map((sample) => sample.cpuUsage ?? 0))
const memorySeries = computed(() =>
  visibleSamples.value.map((sample) => {
    if (!sample.ram.total) {
      return 0
    }

    return (sample.ram.used / sample.ram.total) * 100
  }),
)
const uploadSeries = computed(() => visibleSamples.value.map((sample) => sample.network?.uploadSpeed ?? 0))
const downloadSeries = computed(() => visibleSamples.value.map((sample) => sample.network?.downloadSpeed ?? 0))
const rangeSampleCount = computed(() => visibleSamples.value.length)

const cpuPeakDisplay = computed(() => formatPercent(getPeak(cpuSeries.value)))
const cpuAverageDisplay = computed(() => formatPercent(getAverage(cpuSeries.value)))
const memoryPeakDisplay = computed(() => formatPercent(getPeak(memorySeries.value)))
const memoryAverageDisplay = computed(() => formatPercent(getAverage(memorySeries.value)))
const uploadPeakDisplay = computed(() => formatSpeed(getPeak(uploadSeries.value)))
const uploadAverageDisplay = computed(() => formatSpeed(getAverage(uploadSeries.value)))
const downloadPeakDisplay = computed(() => formatSpeed(getPeak(downloadSeries.value)))
const downloadAverageDisplay = computed(() => formatSpeed(getAverage(downloadSeries.value)))

watch(
  () => sshStore.monitorData,
  (sample) => {
    if (!sample) {
      return
    }

    mergeSamples([sample])
  },
)

watch(
  () => sshStore.connectionId,
  async (connectionId) => {
    samples.value = []
    historyError.value = null

    if (!connectionId) {
      historyLoading.value = false
      return
    }

    historyLoading.value = true
    try {
      const history = await systemApi.getMonitorHistory(connectionId, historyLimit)
      mergeSamples(history)
    } catch (error) {
      console.error('Failed to load monitor history', error)
      historyError.value = error instanceof Error ? error.message : '加载监控历史失败。'
    } finally {
      historyLoading.value = false
    }
  },
  { immediate: true },
)

const cpuChartOption = computed(() =>
  createChartOption({
    area: true,
    formatValue: formatPercent,
    max: 100,
    series: [
      {
        color: '#38bdf8',
        data: cpuSeries.value,
        name: 'CPU',
      },
    ],
  }),
)

const memoryChartOption = computed(() =>
  createChartOption({
    area: true,
    formatValue: formatPercent,
    max: 100,
    series: [
      {
        color: '#fb7185',
        data: memorySeries.value,
        name: '内存',
      },
    ],
  }),
)

const networkChartOption = computed(() =>
  createChartOption({
    formatValue: formatSpeedAxis,
    series: [
      {
        color: '#818cf8',
        data: uploadSeries.value,
        name: '上传',
      },
      {
        color: '#34d399',
        data: downloadSeries.value,
        name: '下载',
      },
    ],
  }),
)

function normalizeSamples(items: MonitorResponse[]) {
  const sampleMap = new Map<number, MonitorResponse>()

  for (const item of items) {
    sampleMap.set(item.timestamp, item)
  }

  return [...sampleMap.values()].sort((left, right) => left.timestamp - right.timestamp).slice(-historyLimit)
}

function mergeSamples(items: MonitorResponse[]) {
  samples.value = normalizeSamples([...samples.value, ...items])
}

function getRangeLimit(range: RangeKey) {
  if (range === '1m') {
    return 20
  }

  if (range === '10m') {
    return historyLimit
  }

  return 100
}

function getAverage(values: number[]) {
  if (values.length === 0) {
    return 0
  }

  return values.reduce((sum, value) => sum + value, 0) / values.length
}

function getPeak(values: number[]) {
  if (values.length === 0) {
    return 0
  }

  return Math.max(...values)
}

function formatMemory(value: number) {
  if (value >= 1024) {
    return `${(value / 1024).toFixed(2)} GB`
  }

  return `${value.toFixed(0)} MB`
}

function formatPercent(value: number) {
  return `${value.toFixed(0)}%`
}

function formatSpeed(value: number) {
  if (value >= 1024 * 1024) {
    return `${(value / 1024 / 1024).toFixed(2)} MB/s`
  }

  if (value >= 1024) {
    return `${(value / 1024).toFixed(1)} KB/s`
  }

  return `${value.toFixed(0)} B/s`
}

function formatSpeedAxis(value: number) {
  if (value >= 1024 * 1024) {
    return `${(value / 1024 / 1024).toFixed(1)} MB/s`
  }

  if (value >= 1024) {
    return `${(value / 1024).toFixed(0)} KB/s`
  }

  return `${value.toFixed(0)} B/s`
}

function formatAxisTime(timestamp: number) {
  return new Intl.DateTimeFormat('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(timestamp))
}

function formatFullTime(timestamp: number) {
  return new Intl.DateTimeFormat('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).format(new Date(timestamp))
}

function createChartOption(config: {
  area?: boolean
  formatValue: (value: number) => string
  max?: number
  series: Array<{
    color: string
    data: number[]
    name: string
  }>
}) {
  const isDark = settingsStore.isDark
  const textColor = isDark ? '#e2e8f0' : '#0f172a'
  const mutedTextColor = isDark ? 'rgba(226,232,240,0.62)' : 'rgba(51,65,85,0.82)'
  const splitLineColor = isDark ? 'rgba(148,163,184,0.12)' : 'rgba(148,163,184,0.18)'
  const axisLineColor = isDark ? 'rgba(148,163,184,0.24)' : 'rgba(148,163,184,0.32)'
  const tooltipBackground = isDark ? 'rgba(15,23,42,0.96)' : 'rgba(255,255,255,0.96)'
  const tooltipBorder = isDark ? 'rgba(148,163,184,0.22)' : 'rgba(148,163,184,0.3)'

  return {
    animation: false,
    grid: {
      bottom: 18,
      containLabel: true,
      left: 16,
      right: 16,
      top: config.series.length > 1 ? 42 : 18,
    },
    legend: config.series.length > 1
      ? {
          icon: 'circle',
          right: 0,
          textStyle: {
            color: mutedTextColor,
          },
          top: 0,
        }
      : undefined,
    textStyle: {
      color: textColor,
      fontFamily: 'inherit',
    },
    tooltip: {
      axisPointer: {
        lineStyle: {
          color: axisLineColor,
        },
        type: 'line',
      },
      backgroundColor: tooltipBackground,
      borderColor: tooltipBorder,
      borderWidth: 1,
      formatter: (params: unknown) => {
        const rows = Array.isArray(params) ? params : [params]
        const firstRow = rows[0] as { axisValue?: number | string } | undefined
        const timestamp = Number(firstRow?.axisValue ?? 0)
        const lines = [
          `<div style="margin-bottom:6px;font-weight:600;">${formatFullTime(timestamp)}</div>`,
        ]

        for (const row of rows) {
          const seriesRow = row as { color?: string; seriesName?: string; value?: number }
          lines.push(
            `<div style="display:flex;align-items:center;justify-content:space-between;gap:12px;min-width:140px;">`
            + `<span style="display:flex;align-items:center;gap:8px;">`
            + `<span style="display:inline-block;width:8px;height:8px;border-radius:999px;background:${seriesRow.color ?? '#94a3b8'};"></span>`
            + `${seriesRow.seriesName ?? '--'}</span>`
            + `<strong>${config.formatValue(Number(seriesRow.value ?? 0))}</strong>`
            + `</div>`,
          )
        }

        return lines.join('')
      },
      trigger: 'axis',
    },
    xAxis: {
      axisLabel: {
        color: mutedTextColor,
        formatter: (value: string | number) => formatAxisTime(Number(value)),
      },
      axisLine: {
        lineStyle: {
          color: axisLineColor,
        },
      },
      axisTick: {
        show: false,
      },
      boundaryGap: false,
      data: chartTimestamps.value,
      type: 'category',
    },
    yAxis: {
      axisLabel: {
        color: mutedTextColor,
        formatter: (value: number) => config.formatValue(value),
      },
      splitLine: {
        lineStyle: {
          color: splitLineColor,
        },
      },
      max: config.max,
      min: 0,
      type: 'value',
    },
    series: config.series.map((item) => ({
      areaStyle: config.area
        ? {
            color: `${item.color}26`,
          }
        : undefined,
      data: item.data,
      lineStyle: {
        color: item.color,
        width: 2,
      },
      name: item.name,
      showSymbol: false,
      smooth: smoothLines.value,
      symbol: 'circle',
      type: 'line',
    })),
  } as EChartsOption
}
</script>

<template>
  <div class="monitor-view h-full overflow-auto p-[20px]" :class="settingsStore.isDark ? 'text-[#e2e8f0]' : 'text-[#0f172a]'">
    <div class="mb-[18px] flex items-start justify-between gap-[16px] lt-md:flex-col">
      <div>
        <div class="text-[0.82rem] uppercase tracking-[0.24em]" :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.9)]' : 'text-[rgba(100,116,139,0.88)]'">
          Performance Monitor
        </div>
        <h2 class="mb-[6px] mt-[10px] text-[26px] font-700">性能监控</h2>
        <p class="m-0 text-[14px]" :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.7)]' : 'text-[rgba(51,65,85,0.82)]'">
          CPU、内存与网络吞吐会先载入缓存历史，再持续接收实时监控推送。
        </p>
      </div>

      <div class="rounded-[18px] px-[16px] py-[14px] backdrop-blur-[16px]"
        :class="settingsStore.isDark
          ? 'border border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.52)]'
          : 'border border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.72)]'">
        <div class="text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'">最新采样</div>
        <div class="mt-[6px] text-[18px] font-700">{{ latestUpdateText }}</div>
        <div class="mt-[8px] text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(191,219,254,0.94)]' : 'text-[rgba(37,99,235,0.88)]'">
          {{ samples.length }} 个缓存点 · 当前显示 {{ visibleRangeLabel }} · 3 秒采样粒度
        </div>
      </div>
    </div>

    <div class="mb-[16px] flex items-center justify-between gap-[12px] lt-md:flex-col lt-md:items-stretch">
      <div class="flex flex-wrap items-center gap-[8px]">
        <span class="text-[13px]" :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.94)]' : 'text-[rgba(100,116,139,0.92)]'">时间范围</span>
        <NButtonGroup>
          <NButton v-for="option in rangeOptions" :key="option.key" size="small"
            :type="selectedRange === option.key ? 'primary' : 'default'"
            :secondary="selectedRange !== option.key" @click="selectedRange = option.key">
            {{ option.label }}
          </NButton>
        </NButtonGroup>
      </div>

      <div class="flex items-center gap-[12px] rounded-[16px] px-[14px] py-[10px] backdrop-blur-[16px]"
        :class="settingsStore.isDark
          ? 'border border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.46)]'
          : 'border border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.72)]'">
        <div>
          <div class="text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'">图表样式</div>
          <div class="text-[14px] font-600">平滑曲线</div>
        </div>
        <NSwitch v-model:value="smoothLines" />
      </div>
    </div>

    <div v-if="monitorError || historyError" class="mb-[16px] grid gap-[12px]">
      <NAlert v-if="historyError" type="warning" :show-icon="true" title="历史数据加载失败">
        {{ historyError }}
      </NAlert>
      <NAlert v-if="monitorError" type="error" :show-icon="true" title="实时监控异常">
        {{ monitorError }}
      </NAlert>
    </div>

    <div class="stats-grid mb-[18px] grid gap-[14px]">
      <div v-for="item in [
        { label: 'CPU 使用率', value: cpuUsageDisplay, detail: `Load ${cpuLoad}` },
        { label: '内存占用', value: ramUsageDisplay, detail: ramDetail },
        { label: '上传速率', value: formatSpeed(uploadSpeed), detail: '当前发送带宽' },
        { label: '下载速率', value: formatSpeed(downloadSpeed), detail: '当前接收带宽' },
        { label: '磁盘占用', value: diskUsage, detail: '根目录空间使用' },
      ]" :key="item.label" class="rounded-[20px] p-[16px] backdrop-blur-[16px]"
        :class="settingsStore.isDark
          ? 'border border-[rgba(148,163,184,0.16)] bg-[linear-gradient(180deg,rgba(15,23,42,0.72),rgba(15,23,42,0.56))]'
          : 'border border-[rgba(148,163,184,0.22)] bg-[linear-gradient(180deg,rgba(255,255,255,0.92),rgba(248,250,252,0.86))]'">
        <div class="text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'">{{ item.label }}</div>
        <div class="mt-[10px] text-[30px] font-700 leading-[1.05]">{{ item.value }}</div>
        <div class="mt-[10px] text-[13px]" :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.68)]' : 'text-[rgba(51,65,85,0.8)]'">{{ item.detail }}</div>
      </div>
    </div>

    <div v-if="hasSamples" class="range-stats-grid mb-[18px] grid gap-[14px]">
      <div v-for="item in [
        { label: 'CPU 区间统计', average: cpuAverageDisplay, peak: cpuPeakDisplay },
        { label: '内存区间统计', average: memoryAverageDisplay, peak: memoryPeakDisplay },
        { label: '上传区间统计', average: uploadAverageDisplay, peak: uploadPeakDisplay },
        { label: '下载区间统计', average: downloadAverageDisplay, peak: downloadPeakDisplay },
      ]" :key="item.label" class="rounded-[20px] p-[16px] backdrop-blur-[16px]"
        :class="settingsStore.isDark
          ? 'border border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.46)]'
          : 'border border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.72)]'">
        <div class="flex items-start justify-between gap-[12px]">
          <div>
            <div class="text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'">{{ item.label }}</div>
            <div class="mt-[6px] text-[13px]" :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.66)]' : 'text-[rgba(51,65,85,0.8)]'">
              {{ visibleRangeLabel }} · {{ rangeSampleCount }} 个采样点
            </div>
          </div>
        </div>
        <div class="mt-[14px] grid grid-cols-2 gap-[12px]">
          <div>
            <div class="text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'">均值</div>
            <div class="mt-[6px] text-[22px] font-700">{{ item.average }}</div>
          </div>
          <div>
            <div class="text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'">峰值</div>
            <div class="mt-[6px] text-[22px] font-700">{{ item.peak }}</div>
          </div>
        </div>
      </div>
    </div>

    <div v-if="historyLoading && !hasSamples"
      class="flex min-h-[420px] items-center justify-center rounded-[24px] backdrop-blur-[16px]"
      :class="settingsStore.isDark
        ? 'border border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.46)]'
        : 'border border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.72)]'">
      <NSpin size="large">
        <template #description>
          载入监控历史中...
        </template>
      </NSpin>
    </div>

    <NEmpty v-else-if="!hasSamples" size="large" description="等待监控数据推送中..."
      class="min-h-[420px] rounded-[24px] backdrop-blur-[16px]"
      :class="settingsStore.isDark
        ? 'border border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.46)]'
        : 'border border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.72)]'" />

    <div v-else class="chart-grid grid gap-[16px]">
      <NCard title="CPU 使用率趋势" :bordered="false" class="monitor-card">
        <template #header-extra>
          <span class="text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'">
            均值 {{ cpuAverageDisplay }} · 峰值 {{ cpuPeakDisplay }}
          </span>
        </template>
        <VChart :option="cpuChartOption" autoresize class="h-[280px] w-full" />
      </NCard>

      <NCard title="内存占用趋势" :bordered="false" class="monitor-card">
        <template #header-extra>
          <span class="text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'">
            均值 {{ memoryAverageDisplay }} · 峰值 {{ memoryPeakDisplay }}
          </span>
        </template>
        <VChart :option="memoryChartOption" autoresize class="h-[280px] w-full" />
      </NCard>

      <NCard title="网络吞吐趋势" :bordered="false" class="monitor-card chart-grid-span-2">
        <template #header-extra>
          <span class="text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'">
            上传均值 {{ uploadAverageDisplay }} · 下载均值 {{ downloadAverageDisplay }}
          </span>
        </template>
        <VChart :option="networkChartOption" autoresize class="h-[320px] w-full" />
      </NCard>
    </div>
  </div>
</template>

<style scoped>
.monitor-view {
  background:
    radial-gradient(circle at top left, rgba(56, 189, 248, 0.16), transparent 30%),
    radial-gradient(circle at top right, rgba(129, 140, 248, 0.14), transparent 28%),
    linear-gradient(180deg, rgba(15, 23, 42, 0.1), rgba(15, 23, 42, 0.04));
  scrollbar-color: rgba(148, 163, 184, 0.55) transparent;
  scrollbar-width: thin;
}

.monitor-view::-webkit-scrollbar {
  width: 10px;
}

.monitor-view::-webkit-scrollbar-track {
  background: transparent;
}

.monitor-view::-webkit-scrollbar-thumb {
  background: linear-gradient(180deg, rgba(96, 165, 250, 0.7), rgba(129, 140, 248, 0.7));
  border: 2px solid transparent;
  border-radius: 999px;
  background-clip: padding-box;
}

.monitor-view::-webkit-scrollbar-thumb:hover {
  background: linear-gradient(180deg, rgba(59, 130, 246, 0.82), rgba(99, 102, 241, 0.82));
  border: 2px solid transparent;
  background-clip: padding-box;
}

.stats-grid {
  grid-template-columns: repeat(5, minmax(0, 1fr));
}

.chart-grid {
  grid-template-columns: repeat(2, minmax(0, 1fr));
}

.range-stats-grid {
  grid-template-columns: repeat(4, minmax(0, 1fr));
}

.chart-grid-span-2 {
  grid-column: span 2;
}

:deep(.monitor-card) {
  border-radius: 24px;
  backdrop-filter: blur(16px);
}

:deep([data-theme='dark'] .monitor-card),
:deep(.dark .monitor-card) {
  background: linear-gradient(180deg, rgba(15, 23, 42, 0.72), rgba(15, 23, 42, 0.56));
}

@media (max-width: 1280px) {
  .range-stats-grid,
  .stats-grid {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
}

@media (max-width: 980px) {
  .chart-grid,
  .range-stats-grid,
  .stats-grid {
    grid-template-columns: 1fr;
  }

  .chart-grid-span-2 {
    grid-column: span 1;
  }
}
</style>
