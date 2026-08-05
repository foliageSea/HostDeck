<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue'
import { Copy, StopFilledAlt } from '@vicons/carbon'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { useDockerOutputStore } from '@/stores/docker-output'
import { useSettingsStore } from '@/stores/settings'

const props = defineProps<{
  taskId: string
  windowId?: string
}>()

const desktopStore = useDesktopStore()
const outputStore = useDockerOutputStore()
const settingsStore = useSettingsStore()
const outputElement = ref<HTMLElement>()
const task = computed(() => outputStore.findTask(props.taskId))

const statusLabel = computed(() => {
  switch (task.value?.status) {
    case 'running':
      return '执行中'
    case 'success':
      return '已完成'
    case 'cancelled':
      return '已停止'
    case 'error':
      return '失败'
    default:
      return '不可用'
  }
})

const statusType = computed(() => {
  switch (task.value?.status) {
    case 'running':
      return 'info'
    case 'success':
      return 'success'
    case 'cancelled':
      return 'warning'
    default:
      return 'error'
  }
})

watch(
  () => task.value?.output.length,
  () => {
    void nextTick(() => {
      if (outputElement.value) {
        outputElement.value.scrollTop = outputElement.value.scrollHeight
      }
    })
  },
  { immediate: true },
)

async function copyOutput() {
  const output = task.value?.output
  if (!output) {
    return
  }
  await navigator.clipboard.writeText(output)
  getUiApi().message.success('输出已复制。')
}

function closeWindow() {
  if (props.windowId) {
    desktopStore.closeWindow(props.windowId)
  }
}
</script>

<template>
  <div class="flex h-full min-h-0 flex-col overflow-hidden">
    <div
      class="flex shrink-0 items-center justify-between gap-[12px] border-b px-[14px] py-[10px]"
      :class="
        settingsStore.isDark
          ? 'border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.5)] text-[#e2e8f0]'
          : 'border-[rgba(148,163,184,0.24)] bg-[rgba(248,250,252,0.72)] text-[#1e293b]'
      "
    >
      <div class="min-w-0">
        <div class="truncate text-[14px] font-600">{{ task?.title || 'Docker 执行输出' }}</div>
        <div v-if="task?.errorMessage" class="mt-[3px] truncate text-[12px] text-[#ef4444]">
          {{ task.errorMessage }}
        </div>
      </div>
      <NTag size="small" :type="statusType">{{ statusLabel }}</NTag>
    </div>

    <pre
      ref="outputElement"
      class="mono-ui m-0 min-h-0 flex-1 overflow-auto whitespace-pre-wrap break-words bg-[#0b1120] px-[14px] py-[12px] text-[12px] leading-[1.6] text-[#d1d5db] app-scrollbar select-text"
      >{{
        task?.output || (task?.status === 'running' ? '正在建立输出流...' : '没有可显示的输出。')
      }}</pre
    >

    <div
      class="flex shrink-0 justify-end gap-[8px] border-t px-[12px] py-[10px]"
      :class="
        settingsStore.isDark
          ? 'border-[rgba(148,163,184,0.14)] bg-[rgba(15,23,42,0.68)]'
          : 'border-[rgba(148,163,184,0.22)] bg-[rgba(248,250,252,0.82)]'
      "
    >
      <NButton :disabled="!task?.output" @click="copyOutput">
        <template #icon
          ><NIcon><Copy /></NIcon
        ></template>
        复制
      </NButton>
      <NButton
        v-if="task?.status === 'running'"
        type="warning"
        @click="outputStore.cancelTask(taskId)"
      >
        <template #icon
          ><NIcon><StopFilledAlt /></NIcon
        ></template>
        停止
      </NButton>
      <NButton @click="closeWindow">关闭</NButton>
    </div>
  </div>
</template>
