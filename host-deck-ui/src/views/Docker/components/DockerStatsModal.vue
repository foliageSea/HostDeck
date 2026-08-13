<script setup lang="ts">
import { computed } from 'vue'
import { LineChart } from 'echarts/charts'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import { use } from 'echarts/core'
import type { EChartsOption } from 'echarts'
import { CanvasRenderer } from 'echarts/renderers'
import VChart from 'vue-echarts'
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'

use([CanvasRenderer, GridComponent, LegendComponent, LineChart, TooltipComponent])

const props = defineProps<{
  controller: DockerViewController
}>()

const settingsStore = useSettingsStore()
const currentSample = computed(
  () => props.controller.statsSamples[props.controller.statsSamples.length - 1] ?? null,
)
const timestamps = computed(() =>
  props.controller.statsSamples.map((sample) => formatTime(sample.timestamp)),
)

const cpuOption = computed(() =>
  createChartOption(
    [
      {
        name: 'CPU',
        color: '#0ea5e9',
        data: props.controller.statsSamples.map((item) => item.cpuPercent),
      },
    ],
    formatPercent,
  ),
)
const memoryOption = computed(() =>
  createChartOption(
    [
      {
        name: '内存',
        color: '#f43f5e',
        data: props.controller.statsSamples.map((item) => item.memoryPercent),
      },
    ],
    formatPercent,
    100,
  ),
)
const networkOption = computed(() =>
  createChartOption(
    [
      {
        name: '接收',
        color: '#10b981',
        data: props.controller.statsSamples.map((item) => item.networkRxBytesPerSecond),
      },
      {
        name: '发送',
        color: '#f59e0b',
        data: props.controller.statsSamples.map((item) => item.networkTxBytesPerSecond),
      },
    ],
    formatSpeed,
  ),
)

function createChartOption(
  series: Array<{ name: string; color: string; data: number[] }>,
  formatter: (value: number) => string,
  max?: number,
) {
  const axisColor = settingsStore.isDark ? 'rgba(148,163,184,0.72)' : 'rgba(71,85,105,0.72)'
  const splitColor = settingsStore.isDark ? 'rgba(148,163,184,0.12)' : 'rgba(148,163,184,0.18)'

  return {
    animation: false,
    grid: { left: 12, right: 16, top: 18, bottom: 8, containLabel: true },
    legend: {
      top: 0,
      right: 8,
      textStyle: { color: axisColor },
    },
    tooltip: {
      trigger: 'axis',
      valueFormatter: (value: unknown) => formatter(Number(value)),
    },
    xAxis: {
      type: 'category',
      boundaryGap: false,
      data: timestamps.value,
      axisLabel: { color: axisColor, hideOverlap: true },
      axisLine: { lineStyle: { color: splitColor } },
      axisTick: { show: false },
    },
    yAxis: {
      type: 'value',
      min: 0,
      max,
      axisLabel: { color: axisColor, formatter: (value: number) => formatter(value) },
      splitLine: { lineStyle: { color: splitColor } },
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
  } as EChartsOption
}

function formatTime(timestamp: number) {
  return new Date(timestamp).toLocaleTimeString('zh-CN', { hour12: false })
}

function formatPercent(value: number) {
  return `${(Number.isFinite(value) ? value : 0).toFixed(1)}%`
}

function formatBytes(value: number) {
  if (!Number.isFinite(value) || value <= 0) {
    return '0 B'
  }
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const unitIndex = Math.max(
    0,
    Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length - 1),
  )
  const size = value / 1024 ** unitIndex
  return `${size.toFixed(size >= 10 || unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`
}

function formatSpeed(value: number) {
  return `${formatBytes(value)}/s`
}
</script>

<template>
  <NModal
    v-model:show="controller.statsVisible"
    preset="card"
    :title="controller.statsTitle"
    class="stats-modal"
    style="width: min(1080px, calc(100vw - 32px))"
  >
    <div class="mb-[12px] flex flex-wrap items-center justify-between gap-[10px]">
      <div class="flex flex-wrap items-center gap-[8px]">
        <NTag
          size="small"
          round
          :type="controller.statsStreamStatus === 'error' ? 'error' : 'success'"
        >
          {{
            controller.statsStreamStatus === 'connecting'
              ? '连接中'
              : controller.statsStreamStatus === 'live'
                ? '实时'
                : controller.statsStreamStatus === 'ended'
                  ? '已结束'
                  : '已断开'
          }}
        </NTag>
        <span class="text-[12px] opacity-65"
          >最近 5 分钟 · {{ controller.statsSamples.length }} 个采样点</span
        >
      </div>
      <NButton size="small" quaternary @click="controller.refreshStatsStream">重新连接</NButton>
    </div>

    <NAlert v-if="controller.statsStreamError" type="error" class="mb-[12px]" :show-icon="true">
      {{ controller.statsStreamError }}
    </NAlert>

    <div class="stats-summary-grid mb-[12px] grid gap-[8px]">
      <div class="stats-summary-item">
        <span>CPU</span>
        <strong>{{ formatPercent(currentSample?.cpuPercent ?? 0) }}</strong>
      </div>
      <div class="stats-summary-item">
        <span>内存</span>
        <strong>{{ formatPercent(currentSample?.memoryPercent ?? 0) }}</strong>
        <small
          >{{ formatBytes(currentSample?.memoryUsage ?? 0) }} /
          {{ formatBytes(currentSample?.memoryLimit ?? 0) }}</small
        >
      </div>
      <div class="stats-summary-item">
        <span>网络接收</span>
        <strong>{{ formatSpeed(currentSample?.networkRxBytesPerSecond ?? 0) }}</strong>
      </div>
      <div class="stats-summary-item">
        <span>网络发送</span>
        <strong>{{ formatSpeed(currentSample?.networkTxBytesPerSecond ?? 0) }}</strong>
      </div>
    </div>

    <NSpin :show="controller.statsStreamStatus === 'connecting' && !controller.statsSamples.length">
      <div class="stats-chart-grid grid gap-[10px]">
        <section class="stats-chart-panel">
          <h3>CPU 使用率</h3>
          <VChart :option="cpuOption" :autoresize="{ throttle: 100 }" class="stats-chart" />
        </section>
        <section class="stats-chart-panel">
          <h3>内存使用率</h3>
          <VChart :option="memoryOption" :autoresize="{ throttle: 100 }" class="stats-chart" />
        </section>
        <section class="stats-chart-panel stats-chart-wide">
          <h3>网络吞吐</h3>
          <VChart :option="networkOption" :autoresize="{ throttle: 100 }" class="stats-chart" />
        </section>
      </div>
    </NSpin>
  </NModal>
</template>

<style scoped>
.stats-summary-grid {
  grid-template-columns: repeat(4, minmax(0, 1fr));
}

.stats-summary-item,
.stats-chart-panel {
  border: 1px solid rgba(148, 163, 184, 0.2);
  border-radius: var(--app-radius-item);
  background: rgba(148, 163, 184, 0.06);
}

.stats-summary-item {
  min-width: 0;
  padding: 10px 12px;
}

.stats-summary-item span,
.stats-summary-item small {
  display: block;
  color: rgba(100, 116, 139, 0.9);
  font-size: 11px;
}

.stats-summary-item strong {
  display: block;
  margin-top: 3px;
  font-size: 18px;
}

.stats-summary-item small {
  margin-top: 2px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.stats-chart-grid {
  grid-template-columns: repeat(2, minmax(0, 1fr));
}

.stats-chart-panel {
  min-width: 0;
  padding: 10px;
}

.stats-chart-panel h3 {
  margin: 0 0 2px;
  font-size: 13px;
  font-weight: 600;
}

.stats-chart-wide {
  grid-column: 1 / -1;
}

.stats-chart {
  width: 100%;
  height: 220px;
}

@media (max-width: 720px) {
  .stats-summary-grid,
  .stats-chart-grid {
    grid-template-columns: 1fr 1fr;
  }

  .stats-chart-panel,
  .stats-chart-wide {
    grid-column: 1 / -1;
  }
}
</style>
