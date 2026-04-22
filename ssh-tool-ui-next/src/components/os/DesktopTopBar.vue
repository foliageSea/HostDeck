<script setup lang="ts">
import { computed } from 'vue'
import { Close, Logout, Moon, Notification, StopFilledAlt, Sun } from '@vicons/carbon'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'
import { useUploadCenterStore, type UploadBatch, type UploadTaskStatus } from '@/stores/upload-center'

const settingsStore = useSettingsStore()
const sshStore = useSshStore()
const desktopStore = useDesktopStore()
const uploadCenterStore = useUploadCenterStore()

const currentTime = computed(() =>
  new Intl.DateTimeFormat('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date()),
)
const sessionStatusMeta = computed(() => {
  if (sshStore.sessionStatus === 'connected') {
    return {
      className: settingsStore.isDark ? 'bg-emerald-400' : 'bg-emerald-500',
      label: 'SSH 会话已连接',
    }
  }

  if (sshStore.sessionStatus === 'reconnecting') {
    return {
      className: settingsStore.isDark ? 'bg-amber-300 animate-pulse' : 'bg-amber-500 animate-pulse',
      label: 'SSH 会话重连中',
    }
  }

  if (sshStore.sessionStatus === 'connecting') {
    return {
      className: settingsStore.isDark ? 'bg-sky-300 animate-pulse' : 'bg-sky-500 animate-pulse',
      label: 'SSH 会话连接中',
    }
  }

  return {
    className: settingsStore.isDark ? 'bg-slate-500' : 'bg-slate-400',
    label: '当前未连接 SSH 会话',
  }
})
const monitorData = computed(() => sshStore.monitorData)
const monitorError = computed(() => sshStore.monitorError)
const cpuUsage = computed(() => {
  if (typeof monitorData.value?.cpuUsage === 'number') {
    return `${monitorData.value.cpuUsage.toFixed(1)}%`
  }

  return '--'
})
const memoryUsage = computed(() => {
  const ram = monitorData.value?.ram
  if (!ram?.total) {
    return '--'
  }

  return `${Math.round((ram.used / ram.total) * 100)}%`
})
const uploadSpeed = computed(() => formatSpeed(monitorData.value?.network?.uploadSpeed ?? 0))
const downloadSpeed = computed(() => formatSpeed(monitorData.value?.network?.downloadSpeed ?? 0))
const performanceStats = computed(() => [
  { label: 'CPU', value: cpuUsage.value },
  { label: '内存', value: memoryUsage.value },
  { label: '上传', value: uploadSpeed.value },
  { label: '下载', value: downloadSpeed.value },
])
const hasUnreadUploads = computed(() => uploadCenterStore.activeTaskCount > 0)
const uploadBatches = computed(() =>
  uploadCenterStore.batches.map((batch) => {
    const totalBytes = batch.tasks.reduce((sum, task) => sum + task.total, 0)
    const loadedBytes = batch.tasks.reduce((sum, task) => sum + task.loaded, 0)
    const completedCount = batch.tasks.filter((task) => task.status === 'success').length
    const cancelledCount = batch.tasks.filter((task) => task.status === 'cancelled').length
    const failedCount = batch.tasks.filter((task) => task.status === 'error').length
    const activeTask = batch.tasks.find((task) => task.status === 'uploading')

    return {
      ...batch,
      cancelledCount,
      completedCount,
      currentFileName: activeTask?.name ?? '',
      failedCount,
      loadedBytes,
      progress: totalBytes > 0 ? Math.min(100, Math.round((loadedBytes / totalBytes) * 100)) : 0,
      totalBytes,
      totalCount: batch.tasks.length,
    }
  }),
)

function formatFileSize(size: number) {
  if (size >= 1024 * 1024 * 1024) {
    return `${(size / 1024 / 1024 / 1024).toFixed(2)} GB`
  }

  if (size >= 1024 * 1024) {
    return `${(size / 1024 / 1024).toFixed(2)} MB`
  }

  if (size >= 1024) {
    return `${(size / 1024).toFixed(1)} KB`
  }

  return `${size} B`
}

function formatUploadStatus(status: UploadTaskStatus) {
  if (status === 'uploading') {
    return '上传中'
  }

  if (status === 'success') {
    return '已完成'
  }

  if (status === 'error') {
    return '失败'
  }

  if (status === 'cancelled') {
    return '已中断'
  }

  return '等待中'
}

function formatBatchTime(timestamp: number) {
  return new Intl.DateTimeFormat('zh-CN', {
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    month: '2-digit',
  }).format(new Date(timestamp))
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

function isBatchActive(batch: UploadBatch) {
  return batch.tasks.some((task) => task.status === 'pending' || task.status === 'uploading')
}

function cancelUploadBatch(batchId: string) {
  uploadCenterStore.cancelBatch(batchId)
}

function handleTaskCenterVisibilityChange(value: boolean) {
  uploadCenterStore.panelOpen = value
}

function disconnect() {
  const dialog = getUiApi().dialog.warning({
    title: '断开连接',
    content: '确认结束当前 SSH 会话并返回登录页？',
    positiveText: '断开',
    negativeText: '取消',
    onPositiveClick: async () => {
      dialog.loading = true
      try {
        desktopStore.reset()
        sshStore.clearSession()
      } finally {
        dialog.loading = false
      }
    },
  })
}
</script>

<template>
  <header
    class="absolute left-0 right-0 top-0 z-20 grid h-[48px] grid-cols-[1fr_auto_1fr] items-center border-b px-[16px] backdrop-blur-[16px]"
    :class="[
      settingsStore.isDark
        ? 'border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.45)] text-[#e2e8f0]'
        : 'border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.58)] text-[#1e293b]',
    ]">
    <div class="flex min-w-0 items-center gap-[12px]">
      <span class="font-700 tracking-[0.04em]">SSH Tool</span>
    </div>

    <div class="flex min-w-0 items-center justify-center gap-[12px] text-[0.92rem]"
      :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.8)]' : 'text-[rgba(51,65,85,0.82)]'">
      <NTooltip placement="bottom">
        <template #trigger>
          <span
            class="h-[10px] w-[10px] shrink-0 rounded-full shadow-[0_0_0_3px_rgba(148,163,184,0.12)]"
            :class="sessionStatusMeta.className"
            :aria-label="sessionStatusMeta.label" />
        </template>
        {{ sessionStatusMeta.label }}
      </NTooltip>
      <NTooltip placement="bottom">
        <template #trigger>
          <div
            class="flex min-w-[120px] max-w-[320px] items-center justify-between gap-[8px] rounded-[10px] px-[10px] py-[4px] text-[12px]"
            :class="settingsStore.isDark
              ? 'bg-[rgba(15,23,42,0.46)] text-[rgba(226,232,240,0.88)]'
              : 'bg-[rgba(255,255,255,0.58)] text-[rgba(30,41,59,0.88)]'">
            <span class="shrink-0 text-[rgba(148,163,184,0.94)]">IP</span>
            <strong class="truncate font-600">{{ sshStore.host || '未连接主机' }}</strong>
          </div>
        </template>
        {{ sshStore.host || '未连接主机' }}
      </NTooltip>
      <NTooltip v-if="monitorError" placement="bottom">
        <template #trigger>
          <div
            class="flex items-center gap-[8px] rounded-[10px] border px-[10px] py-[4px] text-[12px]"
            :class="settingsStore.isDark
              ? 'border-[rgba(248,113,113,0.3)] bg-[rgba(127,29,29,0.28)] text-[rgba(254,202,202,0.96)]'
              : 'border-[rgba(239,68,68,0.24)] bg-[rgba(254,242,242,0.9)] text-[rgba(185,28,28,0.92)]'">
            <span class="h-[8px] w-[8px] shrink-0 rounded-full bg-[currentColor] opacity-90" />
            <strong class="font-600">监控异常</strong>
          </div>
        </template>
        {{ monitorError }}
      </NTooltip>
      <div class="hidden items-center gap-[8px] xl:flex">
        <div v-for="stat in performanceStats" :key="stat.label"
          class="flex min-w-[92px] items-center justify-between gap-[8px] rounded-[10px] px-[10px] py-[4px] text-[12px]"
          :class="settingsStore.isDark
            ? 'bg-[rgba(15,23,42,0.46)] text-[rgba(226,232,240,0.88)]'
            : 'bg-[rgba(255,255,255,0.58)] text-[rgba(30,41,59,0.88)]'">
          <span class="text-[rgba(148,163,184,0.94)]">{{ stat.label }}</span>
          <strong class="font-600">{{ stat.value }}</strong>
        </div>
      </div>
    </div>

    <div class="flex min-w-0 items-center justify-end gap-[12px]">
      <NPopover trigger="click" placement="bottom-end" :show="uploadCenterStore.panelOpen"
        @update:show="handleTaskCenterVisibilityChange">
        <template #trigger>
          <NBadge :value="uploadCenterStore.activeTaskCount" :show="hasUnreadUploads" :max="99" processing>
            <NButton quaternary circle title="任务中心">
              <template #icon>
                <NIcon :size="16">
                  <Notification />
                </NIcon>
              </template>
            </NButton>
          </NBadge>
        </template>

        <div
          class="flex max-h-[min(72vh,720px)] w-[min(460px,calc(100vw_-_24px))] flex-col gap-[14px] rounded-[18px] p-[14px] backdrop-blur-[18px] lt-md:max-h-[68vh] lt-md:w-[min(420px,calc(100vw_-_16px))]">
          <div class="flex items-start justify-between gap-[12px]">
            <div>
              <div class="text-[14px] font-700">任务中心</div>
              <div class="text-[12px]"
                :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.94)]' : 'text-[rgba(100,116,139,0.92)]'">
                {{ uploadCenterStore.totalTaskCount }} 个上传任务
                <template v-if="uploadCenterStore.activeTaskCount > 0">
                  ，{{ uploadCenterStore.activeTaskCount }} 个进行中
                </template>
              </div>
            </div>
            <div class="flex items-center gap-[8px]">
              <NButton quaternary size="small" :disabled="!uploadCenterStore.hasTasks"
                @click="uploadCenterStore.clearFinished()">
                清除已完成
              </NButton>
              <NButton quaternary circle size="small" @click="uploadCenterStore.closePanel()">
                <template #icon>
                  <NIcon :size="14">
                    <Close />
                  </NIcon>
                </template>
              </NButton>
            </div>
          </div>

          <div v-if="uploadBatches.length === 0" class="text-[12px]"
            :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.94)]' : 'text-[rgba(100,116,139,0.92)]'">
            当前没有上传任务
          </div>

          <div v-else class="flex flex-col gap-[12px] overflow-auto pr-[2px]">
            <div v-for="batch in uploadBatches" :key="batch.id" class="flex flex-col gap-[10px] rounded-[16px] p-[12px]"
              :class="[
                settingsStore.isDark
                  ? 'border border-[rgba(148,163,184,0.16)] bg-[rgba(30,41,59,0.52)]'
                  : 'border border-[rgba(148,163,184,0.2)] bg-[linear-gradient(180deg,rgba(248,250,252,0.98),rgba(241,245,249,0.98))]',
                isBatchActive(batch)
                  ? settingsStore.isDark
                    ? 'border-[rgba(96,165,250,0.34)]'
                    : 'border-[rgba(59,130,246,0.32)] shadow-[inset_0_0_0_1px_rgba(191,219,254,0.7)]'
                  : '',
              ]">
              <div class="flex items-start justify-between gap-[12px] lt-md:flex-col">
                <div>
                  <div class="truncate-line text-[13px] font-600" :class="settingsStore.isDark ? '' : 'text-[#0f172a]'">
                    文件上传 ·
                    {{ batch.path }}</div>
                  <div class="text-[12px]"
                    :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.94)]' : 'text-[rgba(100,116,139,0.92)]'">
                    {{ formatBatchTime(batch.createdAt) }}
                    <template v-if="batch.currentFileName">
                      · 正在上传 {{ batch.currentFileName }}
                    </template>
                    · {{ batch.completedCount }}/{{ batch.totalCount }} 完成
                    <template v-if="batch.cancelledCount > 0">
                      · {{ batch.cancelledCount }} 已中断
                    </template>
                    <template v-if="batch.failedCount > 0">
                      · {{ batch.failedCount }} 失败
                    </template>
                  </div>
                </div>
                <div class="flex flex-col items-end gap-[8px] lt-md:items-start">
                  <div class="flex flex-col items-end gap-[4px] text-[12px] lt-md:items-start"
                    :class="settingsStore.isDark ? 'text-[rgba(191,219,254,0.96)]' : 'text-[rgba(37,99,235,0.86)]'">
                    <span>{{ batch.progress }}%</span>
                    <span>{{ formatFileSize(batch.loadedBytes) }} / {{ formatFileSize(batch.totalBytes) }}</span>
                  </div>
                  <NButton v-if="isBatchActive(batch)" quaternary size="tiny" @click="cancelUploadBatch(batch.id)">
                    <template #icon>
                      <NIcon :size="14">
                        <StopFilledAlt />
                      </NIcon>
                    </template>
                    中断上传
                  </NButton>
                </div>
              </div>

              <NProgress type="line" :percentage="batch.progress" :show-indicator="false"
                :processing="isBatchActive(batch)" />

              <div v-if="batch.errorMessage" class="text-[12px]"
                :class="settingsStore.isDark ? 'text-[rgba(248,113,113,0.96)]' : 'text-[rgba(220,38,38,0.92)]'">
                {{ batch.errorMessage }}
              </div>

              <div class="flex flex-col gap-[8px]">
                <div v-for="task in batch.tasks" :key="task.id" class="flex flex-col gap-[8px] rounded-[12px] p-[10px]"
                  :class="[
                    settingsStore.isDark
                      ? 'border border-[rgba(148,163,184,0.12)] bg-[rgba(15,23,42,0.52)]'
                      : 'border border-[rgba(148,163,184,0.18)] bg-[rgba(255,255,255,0.98)]',
                    task.status === 'uploading'
                      ? settingsStore.isDark ? 'border-[rgba(96,165,250,0.28)]' : 'border-[rgba(59,130,246,0.28)]'
                      : '',
                    task.status === 'success'
                      ? settingsStore.isDark ? 'border-[rgba(74,222,128,0.24)]' : 'border-[rgba(34,197,94,0.24)]'
                      : '',
                    task.status === 'error'
                      ? settingsStore.isDark ? 'border-[rgba(248,113,113,0.28)]' : 'border-[rgba(239,68,68,0.24)]'
                      : '',
                  ]">
                  <div class="flex items-start justify-between gap-[12px] lt-md:flex-col">
                    <div class="truncate-line" :class="settingsStore.isDark ? '' : 'text-[#0f172a]'" :title="task.name">
                      {{
                        task.name }}</div>
                    <NTag size="small"
                      :type="task.status === 'error' ? 'error' : task.status === 'success' ? 'success' : task.status === 'cancelled' ? 'warning' : 'info'">
                      {{ formatUploadStatus(task.status) }}
                    </NTag>
                  </div>
                  <div class="flex items-start justify-between gap-[12px] text-[12px] lt-md:flex-col"
                    :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.94)]' : 'text-[rgba(100,116,139,0.92)]'">
                    <span>{{ formatFileSize(task.loaded) }} / {{ formatFileSize(task.total) }}</span>
                    <span>{{ task.progress }}%</span>
                  </div>
                  <NProgress type="line" :percentage="task.progress"
                    :status="task.status === 'error' ? 'error' : task.status === 'success' ? 'success' : task.status === 'cancelled' ? 'warning' : 'default'"
                    :show-indicator="false" :processing="task.status === 'uploading'" />
                </div>
              </div>
            </div>
          </div>
        </div>
      </NPopover>

      <NButton quaternary circle title="断开连接" @click="disconnect">
        <template #icon>
          <NIcon :size="16">
            <Logout />
          </NIcon>
        </template>
      </NButton>
      <NButton quaternary circle :title="settingsStore.isDark ? '切换浅色模式' : '切换深色模式'" @click="settingsStore.toggleTheme">
        <template #icon>
          <NIcon :size="16">
            <component :is="settingsStore.isDark ? Sun : Moon" />
          </NIcon>
        </template>
      </NButton>
      <span>{{ currentTime }}</span>
    </div>
  </header>
</template>
