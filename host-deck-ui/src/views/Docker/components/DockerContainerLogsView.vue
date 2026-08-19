<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { dockerApi } from '@/api/docker'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'

const props = defineProps<{ connectionId: string; containerId: string; containerName: string }>()

const settingsStore = useSettingsStore()
const logsElement = ref<HTMLElement>()
const content = ref('')
const tail = ref(200)
const keyword = ref('')
const loading = ref(false)
const refreshing = ref(false)
const status = ref<'connecting' | 'live' | 'ended' | 'error'>('connecting')
const error = ref('')
const lastUpdatedAt = ref<Date | null>(null)
const followLogs = ref(true)
let abortController: AbortController | null = null
let generation = 0

const displayedLogs = computed(() => {
  const search = keyword.value.trim().toLowerCase()
  return search
    ? content.value
        .split(/\r?\n/)
        .filter((line) => line.toLowerCase().includes(search))
        .join('\n')
    : content.value
})

function stopStream() {
  generation += 1
  abortController?.abort()
  abortController = null
}

function appendLogs(text: string) {
  const maxLength = 2 * 1024 * 1024
  content.value = `${content.value}${text}`.slice(-maxLength)
  lastUpdatedAt.value = new Date()
}

async function refreshLogs() {
  stopStream()
  const currentGeneration = generation
  const controller = new AbortController()
  abortController = controller
  content.value = ''
  error.value = ''
  status.value = 'connecting'
  loading.value = true
  refreshing.value = true
  followLogs.value = true

  try {
    await dockerApi.streamContainerLogs(
      props.connectionId,
      props.containerId,
      { tail: tail.value, timestamps: true },
      (event) => {
        if (currentGeneration !== generation) return
        if (event.event === 'connected') {
          status.value = 'live'
        } else if (event.event === 'stdout' || event.event === 'stderr') {
          status.value = 'live'
          appendLogs(event.data.text)
        } else if (event.event === 'done') {
          status.value = 'ended'
        }
        loading.value = false
        refreshing.value = false
      },
      controller.signal,
    )
  } catch (caughtError) {
    if (!controller.signal.aborted && currentGeneration === generation) {
      status.value = 'error'
      error.value = caughtError instanceof Error ? caughtError.message : '日志加载失败。'
    }
  } finally {
    if (currentGeneration === generation) {
      loading.value = false
      refreshing.value = false
    }
  }
}

async function copyLogs() {
  try {
    await navigator.clipboard.writeText(displayedLogs.value)
    getUiApi().message.success('日志已复制到剪贴板。')
  } catch {
    getUiApi().message.error('复制日志失败。')
  }
}

function downloadLogs() {
  const url = URL.createObjectURL(
    new Blob([displayedLogs.value], { type: 'text/plain;charset=utf-8' }),
  )
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = `${props.containerName || 'container'}-${Date.now()}.log`
  anchor.click()
  URL.revokeObjectURL(url)
}

function handleScroll() {
  const element = logsElement.value
  if (element)
    followLogs.value = element.scrollHeight - element.scrollTop - element.clientHeight <= 24
}

watch(
  () => displayedLogs.value.length,
  () => {
    void nextTick(() => {
      if (followLogs.value && logsElement.value)
        logsElement.value.scrollTop = logsElement.value.scrollHeight
    })
  },
)
watch(tail, () => void refreshLogs())
onMounted(() => void refreshLogs())
onBeforeUnmount(stopStream)
</script>

<template>
  <div class="flex h-full min-h-0 flex-col gap-[12px] p-[16px]">
    <div class="flex flex-wrap items-center gap-[10px]">
      <NInputNumber v-model:value="tail" class="w-[112px]" :min="20" :max="5000" :step="20" />
      <NInput
        v-model:value="keyword"
        class="min-w-[180px] flex-1"
        placeholder="过滤日志关键字"
        clearable
      />
      <NButton quaternary :loading="refreshing" @click="refreshLogs">重新连接</NButton>
      <NButton quaternary @click="copyLogs">复制</NButton>
      <NButton quaternary @click="downloadLogs">下载</NButton>
    </div>
    <NSpin :show="loading" class="min-h-0 flex-1">
      <pre
        ref="logsElement"
        class="docker-console app-scrollbar m-0 h-full overflow-auto whitespace-pre-wrap break-words rounded-[14px] p-[14px] text-[12px] leading-[1.6] select-text"
        :class="
          settingsStore.isDark
            ? 'bg-[rgba(2,6,23,0.9)] text-[#dbeafe] app-scrollbar-dark'
            : 'bg-[rgba(248,250,252,0.96)] text-[rgba(30,41,59,0.96)] app-scrollbar-light'
        "
        @scroll="handleScroll"
        >{{ displayedLogs }}</pre
      >
    </NSpin>
    <div class="flex items-center justify-between gap-[12px] text-[12px] opacity-70">
      <span>最近日志 {{ lastUpdatedAt?.toLocaleString('zh-CN') ?? '-' }}</span>
      <span :class="status === 'error' ? 'text-red-500' : 'text-emerald-500'">{{
        status === 'connecting'
          ? '连接中'
          : status === 'live'
            ? '实时'
            : status === 'ended'
              ? '已结束'
              : error || '已断开'
      }}</span>
    </div>
  </div>
</template>
