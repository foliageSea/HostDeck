<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue'
import {
  Activity,
  ArrowDownToLine,
  Clock3,
  Cpu,
  Gauge,
  MemoryStick,
  Pause,
  Play,
  RotateCw,
  Trash2,
} from '@lucide/vue'
import type { SelectOption } from 'naive-ui'
import type { RealtimeLogItem } from '@/api/logs'
import { useSettingsStore } from '@/stores/settings'
import { useRealtimeLogs } from './useRealtimeLogs'
import { useServerMetrics } from './useServerMetrics'

const settingsStore = useSettingsStore()
const controller = useRealtimeLogs()
const metrics = useServerMetrics()
const logElement = ref<HTMLElement>()
const level = ref('')
const logger = ref('')
const keyword = ref('')
const autoScroll = ref(true)
const followsLatest = ref(true)

const levelOptions: SelectOption[] = [
  { label: '全部级别', value: '' },
  { label: 'SHOUT', value: 'SHOUT' },
  { label: 'SEVERE', value: 'SEVERE' },
  { label: 'WARNING', value: 'WARNING' },
  { label: 'INFO', value: 'INFO' },
  { label: 'CONFIG', value: 'CONFIG' },
  { label: 'FINE', value: 'FINE' },
  { label: 'FINER', value: 'FINER' },
  { label: 'FINEST', value: 'FINEST' },
]

const loggerOptions = computed<SelectOption[]>(() => [
  { label: '全部 Logger', value: '' },
  ...Array.from(new Set(controller.logs.value.map((item) => item.logger)))
    .sort((left, right) => left.localeCompare(right))
    .map((value) => ({ label: value, value })),
])

const filteredLogs = computed(() => {
  const normalizedKeyword = keyword.value.trim().toLocaleLowerCase()
  return controller.logs.value.filter((item) => {
    if (level.value && item.level.toUpperCase() !== level.value) {
      return false
    }
    if (logger.value && item.logger !== logger.value) {
      return false
    }
    if (!normalizedKeyword) {
      return true
    }
    return [item.logger, item.message, item.error, item.stackTrace]
      .filter((value): value is string => Boolean(value))
      .some((value) => value.toLocaleLowerCase().includes(normalizedKeyword))
  })
})

const statusLabel = computed(() => {
  if (controller.connectionStatus.value === 'connected') return '实时'
  if (controller.connectionStatus.value === 'connecting') return '连接中'
  if (controller.connectionStatus.value === 'reconnecting') return '重连中'
  if (controller.connectionStatus.value === 'unauthorized') return '登录已失效'
  return '已停止'
})

function formatTime(value: RealtimeLogItem['timestamp']) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) {
    return String(value)
  }
  return new Intl.DateTimeFormat('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    fractionalSecondDigits: 3,
    hour12: false,
  }).format(date)
}

function levelClass(value: string) {
  const normalized = value.toUpperCase()
  if (normalized === 'SEVERE' || normalized === 'SHOUT') return 'level-error'
  if (normalized === 'WARNING') return 'level-warn'
  if (normalized === 'CONFIG' || normalized.startsWith('FINE')) return 'level-debug'
  return 'level-info'
}

function scrollToLatest() {
  followsLatest.value = true
  void nextTick(() => {
    if (logElement.value) {
      logElement.value.scrollTop = logElement.value.scrollHeight
    }
  })
}

function handleScroll() {
  const element = logElement.value
  if (!element) return
  followsLatest.value = element.scrollHeight - element.scrollTop - element.clientHeight <= 32
}

function togglePaused() {
  controller.setPaused(!controller.paused.value)
}

function reconnectStreams() {
  controller.reconnect()
  metrics.reconnect()
}

function formatBytes(value?: number) {
  if (value === undefined) return '--'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let size = value
  let unitIndex = 0
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024
    unitIndex += 1
  }
  const precision = unitIndex === 0 ? 0 : size >= 100 ? 0 : 1
  return `${size.toFixed(precision)} ${units[unitIndex]}`
}

function formatUptime(value?: number) {
  if (value === undefined) return '--'
  const totalSeconds = Math.floor(value / 1000)
  const days = Math.floor(totalSeconds / 86400)
  const hours = Math.floor((totalSeconds % 86400) / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  if (days > 0) return `${days}天 ${hours}小时`
  if (hours > 0) return `${hours}小时 ${minutes}分`
  return `${minutes}分 ${totalSeconds % 60}秒`
}

function formatCpu(value?: number | null) {
  return value === undefined || value === null ? '--' : `${value.toFixed(1)}%`
}

function formatLag(value?: number) {
  return value === undefined ? '--' : `${value.toFixed(value >= 10 ? 0 : 1)} ms`
}

watch(
  () => filteredLogs.value.length,
  () => {
    if (autoScroll.value && followsLatest.value) {
      scrollToLatest()
    }
  },
)

watch(autoScroll, (enabled) => {
  if (enabled) scrollToLatest()
})
</script>

<template>
  <div
    class="realtime-logs h-full min-h-0 flex flex-col"
    :class="settingsStore.isDark ? 'realtime-logs-dark' : 'realtime-logs-light'"
  >
    <div class="log-toolbar flex flex-wrap items-center gap-[8px] px-[12px] py-[9px]">
      <NSelect v-model:value="level" class="w-[112px]" size="small" :options="levelOptions" />
      <NSelect
        v-model:value="logger"
        class="w-[170px]"
        clearable
        filterable
        size="small"
        :options="loggerOptions"
      />
      <NInput
        v-model:value="keyword"
        class="min-w-[150px] flex-1"
        clearable
        placeholder="搜索消息、错误或堆栈"
        size="small"
      />

      <div class="toolbar-actions flex items-center gap-[5px]">
        <NTooltip>
          <template #trigger>
            <NButton size="small" secondary @click="togglePaused">
              <template #icon><component :is="controller.paused.value ? Play : Pause" /></template>
              {{ controller.paused.value ? '继续' : '暂停' }}
            </NButton>
          </template>
          {{ controller.paused.value ? '显示缓冲的日志并继续更新' : '冻结显示，后台继续接收日志' }}
        </NTooltip>
        <div class="auto-scroll-control flex items-center gap-[6px] px-[7px] text-[12px]">
          <span>自动滚动</span>
          <NSwitch v-model:value="autoScroll" size="small" />
        </div>
        <NTooltip>
          <template #trigger>
            <NButton aria-label="清空日志" size="small" quaternary @click="controller.clear">
              <template #icon><Trash2 /></template>
            </NButton>
          </template>
          清空当前日志
        </NTooltip>
        <NTooltip>
          <template #trigger>
            <NButton aria-label="重新连接" size="small" quaternary @click="reconnectStreams">
              <template #icon><RotateCw /></template>
            </NButton>
          </template>
          重新连接日志流
        </NTooltip>
      </div>
    </div>

    <div class="metrics-strip" aria-label="服务运行指标">
      <div class="metrics-heading">
        <Activity :size="14" />
        <span>服务进程</span>
        <span class="metrics-dot" :class="`metrics-${metrics.connectionStatus.value}`" />
      </div>
      <div class="metric-item">
        <Cpu :size="14" />
        <span class="metric-label">CPU</span>
        <strong>{{ formatCpu(metrics.snapshot.value?.cpuPercent) }}</strong>
      </div>
      <div class="metric-item">
        <MemoryStick :size="14" />
        <span class="metric-label">内存</span>
        <strong>{{ formatBytes(metrics.snapshot.value?.rssBytes) }}</strong>
        <span class="metric-secondary"
          >峰值 {{ formatBytes(metrics.snapshot.value?.peakRssBytes) }}</span
        >
      </div>
      <div class="metric-item">
        <Gauge :size="14" />
        <span class="metric-label">事件循环</span>
        <strong>{{ formatLag(metrics.snapshot.value?.eventLoopLagMs) }}</strong>
      </div>
      <div class="metric-item">
        <Clock3 :size="14" />
        <span class="metric-label">运行</span>
        <strong>{{ formatUptime(metrics.snapshot.value?.uptimeMs) }}</strong>
      </div>
    </div>

    <div
      ref="logElement"
      class="log-output app-scrollbar min-h-0 flex-1 overflow-auto"
      @scroll="handleScroll"
    >
      <div v-if="filteredLogs.length === 0" class="log-empty">等待日志...</div>
      <div v-for="item in filteredLogs" :key="item.id" class="log-entry">
        <div class="log-line">
          <span class="log-time">{{ formatTime(item.timestamp) }}</span>
          <span class="log-level" :class="levelClass(item.level)">{{
            item.level.toUpperCase()
          }}</span>
          <span class="log-logger">{{ item.logger }}</span>
          <span class="log-message">{{ item.message }}</span>
        </div>
        <div v-if="item.error" class="log-error">{{ item.error }}</div>
        <pre v-if="item.stackTrace" class="log-stack">{{ item.stackTrace }}</pre>
      </div>
    </div>

    <button
      v-if="autoScroll && !followsLatest"
      class="jump-latest"
      type="button"
      @click="scrollToLatest"
    >
      <ArrowDownToLine :size="14" />
      跳到最新
    </button>

    <div
      class="log-statusbar flex items-center justify-between gap-[10px] px-[12px] py-[6px] text-[11px]"
    >
      <div class="min-w-0 flex items-center gap-[8px]">
        <span class="status-dot" :class="`status-${controller.connectionStatus.value}`" />
        <span>{{ statusLabel }}</span>
        <span
          v-if="controller.connectionError.value"
          class="truncate"
          :title="controller.connectionError.value"
        >
          {{ controller.connectionError.value }}
        </span>
        <span
          v-if="controller.replayTruncated.value"
          title="断线期间的部分旧日志已离开服务端缓冲区"
        >
          回放已截断
        </span>
      </div>
      <div class="flex-none">
        显示 {{ filteredLogs.length }}/{{ controller.logs.value.length }} · 已接收
        {{ controller.receivedCount.value }}
        <span v-if="controller.paused.value"> · 待显示 {{ controller.bufferedCount.value }}</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.realtime-logs {
  position: relative;
  color: #d7dee9;
  background: #0b1018;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', monospace;
}

.log-toolbar,
.metrics-strip,
.log-statusbar {
  z-index: 1;
  flex: none;
  border-color: rgba(148, 163, 184, 0.18);
  background: #121925;
}

.log-toolbar {
  border-bottom: 1px solid rgba(148, 163, 184, 0.18);
}
.metrics-strip {
  display: flex;
  min-height: 38px;
  align-items: center;
  gap: 0;
  overflow-x: auto;
  border-bottom: 1px solid rgba(148, 163, 184, 0.18);
  color: #aab5c4;
  scrollbar-width: none;
}
.metrics-strip::-webkit-scrollbar {
  display: none;
}
.metrics-heading,
.metric-item {
  display: flex;
  height: 38px;
  flex: none;
  align-items: center;
  gap: 6px;
  padding: 0 12px;
  border-right: 1px solid rgba(148, 163, 184, 0.14);
  font-size: 11px;
  white-space: nowrap;
}
.metrics-heading {
  color: #d7dee9;
  font-weight: 700;
}
.metrics-heading > svg,
.metric-item > svg {
  color: #38bdf8;
}
.metric-item strong {
  color: #e2e8f0;
  font-size: 12px;
  font-variant-numeric: tabular-nums;
}
.metric-label,
.metric-secondary {
  color: #748094;
}
.metrics-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: #64748b;
}
.metrics-connected {
  background: #22c55e;
}
.metrics-connecting,
.metrics-reconnecting {
  background: #f59e0b;
}
.log-statusbar {
  border-top: 1px solid rgba(148, 163, 184, 0.18);
  color: #94a3b8;
}
.auto-scroll-control {
  height: 28px;
  color: #aab5c4;
}
.log-output {
  padding: 7px 0 16px;
  background: #0b1018;
}
.log-entry {
  padding: 2px 12px;
  border-left: 2px solid transparent;
}
.log-entry:hover {
  background: rgba(148, 163, 184, 0.07);
  border-left-color: #38bdf8;
}
.log-line {
  display: grid;
  grid-template-columns: 96px 52px minmax(100px, 190px) minmax(220px, 1fr);
  gap: 9px;
  align-items: baseline;
  font-size: 12px;
  line-height: 1.55;
}
.log-time {
  color: #748094;
  font-variant-numeric: tabular-nums;
}
.log-level {
  font-weight: 700;
}
.level-info {
  color: #4ade80;
}
.level-debug {
  color: #94a3b8;
}
.level-warn {
  color: #fbbf24;
}
.level-error {
  color: #fb7185;
}
.log-logger {
  overflow: hidden;
  color: #67e8f9;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.log-message {
  min-width: 0;
  color: #d7dee9;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
.log-error,
.log-stack {
  margin: 2px 0 4px 166px;
  padding: 5px 8px;
  border-left: 2px solid #fb7185;
  color: #fecdd3;
  background: rgba(127, 29, 29, 0.2);
  font: inherit;
  font-size: 11px;
  line-height: 1.55;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
.log-stack {
  color: #fda4af;
}
.log-empty {
  padding: 30px 12px;
  color: #64748b;
  text-align: center;
  font-size: 12px;
}
.jump-latest {
  position: absolute;
  right: 16px;
  bottom: 38px;
  display: flex;
  align-items: center;
  gap: 6px;
  height: 28px;
  padding: 0 9px;
  border: 1px solid rgba(56, 189, 248, 0.42);
  border-radius: 6px;
  color: #bae6fd;
  background: #172337;
  font: inherit;
  font-size: 11px;
  cursor: pointer;
}
.jump-latest:hover {
  background: #1d3049;
}
.status-dot {
  width: 7px;
  height: 7px;
  flex: none;
  border-radius: 50%;
  background: #64748b;
}
.status-connected {
  background: #22c55e;
  box-shadow: 0 0 0 3px rgba(34, 197, 94, 0.12);
}
.status-connecting,
.status-reconnecting {
  background: #f59e0b;
}
.status-unauthorized {
  background: #ef4444;
}

.realtime-logs-light {
  color: #263244;
  background: #f8fafc;
}
.realtime-logs-light .log-toolbar,
.realtime-logs-light .metrics-strip,
.realtime-logs-light .log-statusbar {
  border-color: #d9e0e9;
  background: #eef2f6;
}
.realtime-logs-light .metrics-strip {
  color: #526176;
}
.realtime-logs-light .metrics-heading,
.realtime-logs-light .metric-item strong {
  color: #263244;
}
.realtime-logs-light .metric-label,
.realtime-logs-light .metric-secondary {
  color: #778397;
}
.realtime-logs-light .log-output {
  background: #f8fafc;
}
.realtime-logs-light .log-message {
  color: #263244;
}
.realtime-logs-light .log-logger {
  color: #087b8c;
}
.realtime-logs-light .log-time {
  color: #778397;
}
.realtime-logs-light .level-info {
  color: #15803d;
}
.realtime-logs-light .level-debug {
  color: #64748b;
}
.realtime-logs-light .level-warn {
  color: #b45309;
}
.realtime-logs-light .level-error {
  color: #be123c;
}
.realtime-logs-light .log-entry:hover {
  background: #edf3f8;
}
.realtime-logs-light .auto-scroll-control {
  color: #526176;
}
.realtime-logs-light .log-error,
.realtime-logs-light .log-stack {
  color: #9f1239;
  background: #fff1f2;
}
.realtime-logs-light .jump-latest {
  color: #075985;
  background: #e0f2fe;
}

@media (max-width: 760px) {
  .log-toolbar > :deep(.n-select) {
    width: calc(50% - 4px);
  }
  .log-toolbar > :deep(.n-input) {
    flex-basis: 100%;
  }
  .toolbar-actions {
    width: 100%;
  }
  .log-line {
    grid-template-columns: 88px 48px minmax(0, 1fr);
    gap: 7px;
  }
  .log-logger {
    grid-column: 3;
  }
  .log-message {
    grid-column: 1 / -1;
    padding-left: 95px;
  }
  .log-error,
  .log-stack {
    margin-left: 95px;
  }
  .log-statusbar {
    align-items: flex-start;
    flex-direction: column;
  }
}
</style>
