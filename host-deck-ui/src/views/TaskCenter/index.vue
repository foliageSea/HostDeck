<script setup lang="ts">
import { computed, ref } from 'vue'
import { Ellipsis, Folder, Trash2, XCircle } from '@lucide/vue'
import { filesApi, type FileTask } from '@/api/files'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'
import {
  useUploadCenterStore,
  type UploadBatch,
  type UploadTaskSource,
  type UploadTaskStatus,
} from '@/stores/upload-center'

type TaskTab = 'uploads' | 'files' | 'other'

const settingsStore = useSettingsStore()
const uploadCenterStore = useUploadCenterStore()
const activeTab = ref<TaskTab>('uploads')

const tabs: Array<{ label: string; value: TaskTab }> = [
  { label: '上传', value: 'uploads' },
  { label: '文件任务', value: 'files' },
  { label: '其它任务', value: 'other' },
]

function getTaskTab(source: UploadTaskSource): TaskTab {
  if (source === 'files') return 'uploads'
  if (source.startsWith('files-')) return 'files'
  return 'other'
}

const visibleBatches = computed(() =>
  uploadCenterStore.batches.filter((batch) => getTaskTab(batch.source) === activeTab.value),
)
const hasActiveTasks = computed(() =>
  uploadCenterStore.batches.some((batch) => isBatchActive(batch)),
)
const hasFinishedTasks = computed(() =>
  uploadCenterStore.batches.some((batch) => !isBatchActive(batch)),
)

function isTaskActive(status: UploadTaskStatus) {
  return ['pending', 'processing', 'uploading', 'downloading'].includes(status)
}

function isBatchActive(batch: UploadBatch) {
  return batch.tasks.some((task) => isTaskActive(task.status))
}

function getBatchProgress(batch: UploadBatch) {
  const total = batch.tasks.reduce((sum, task) => sum + task.total, 0)
  const loaded = batch.tasks.reduce((sum, task) => sum + task.loaded, 0)
  if (total > 0) return Math.min(100, Math.round((loaded / total) * 100))

  return batch.tasks.length > 0
    ? Math.round(batch.tasks.reduce((sum, task) => sum + task.progress, 0) / batch.tasks.length)
    : 0
}

function getCompletedCount(batch: UploadBatch) {
  return batch.tasks.filter((task) => task.status === 'success').length
}

function getBatchStatus(batch: UploadBatch): UploadTaskStatus {
  const statuses = batch.tasks.map((task) => task.status)
  if (statuses.some((status) => status === 'error')) return 'error'
  if (statuses.some((status) => status === 'downloading')) return 'downloading'
  if (statuses.some((status) => status === 'uploading')) return 'uploading'
  if (statuses.some((status) => status === 'processing')) return 'processing'
  if (statuses.some((status) => status === 'pending')) return 'pending'
  if (statuses.every((status) => status === 'success')) return 'success'
  return 'cancelled'
}

function getStatusLabel(status: UploadTaskStatus) {
  const labels: Record<UploadTaskStatus, string> = {
    cancelled: '已中断',
    downloading: '下载中',
    error: '失败',
    pending: '等待中',
    processing: '处理中',
    success: '已完成',
    uploading: '上传中',
  }
  return labels[status]
}

function getStatusType(status: UploadTaskStatus) {
  if (status === 'success') return 'success'
  if (status === 'error') return 'error'
  if (status === 'cancelled') return 'warning'
  return 'info'
}

function getSourceLabel(source: UploadTaskSource) {
  const labels: Record<UploadTaskSource, string> = {
    'docker-image-export': '镜像导出',
    'docker-image-import': '镜像导入',
    files: '上传',
    'files-compress': '压缩',
    'files-copy': '复制',
    'files-delete': '删除',
    'files-download': '下载',
    'files-extract': '解压',
    'files-move': '移动',
  }
  return labels[source]
}

function getBatchTitle(batch: UploadBatch) {
  if (batch.tasks.length === 1) return batch.tasks[0]?.name ?? batch.path
  return `${batch.tasks[0]?.name ?? batch.path} 等 ${batch.tasks.length} 项`
}

function cancelBatch(batch: UploadBatch) {
  if (batch.source.startsWith('files-') && batch.source !== 'files-download') {
    void filesApi
      .cancelTask(batch.id)
      .then((task: FileTask) => uploadCenterStore.upsertRemoteTask(task))
    return
  }
  uploadCenterStore.cancelBatch(batch.id)
}

function cancelAll() {
  uploadCenterStore.batches.filter(isBatchActive).forEach(cancelBatch)
}

function clearAll() {
  getUiApi().dialog.warning({
    title: '删除全部任务',
    content: hasActiveTasks.value
      ? '进行中的任务将被中断，确认删除全部任务？'
      : '确认删除全部任务记录？',
    positiveText: '删除',
    negativeText: '取消',
    onPositiveClick: () => uploadCenterStore.clearAll(),
  })
}

function getRowOptions(batch: UploadBatch) {
  return isBatchActive(batch)
    ? [{ key: 'cancel', label: '中断任务' }]
    : [{ key: 'remove', label: '删除记录' }]
}

function handleRowAction(key: string | number, batch: UploadBatch) {
  if (key === 'cancel') cancelBatch(batch)
  if (key === 'remove') uploadCenterStore.removeBatch(batch.id)
}
</script>

<template>
  <section
    class="task-center flex h-full min-h-0 flex-col overflow-hidden"
    :class="settingsStore.isDark ? 'text-[#e2e8f0]' : 'text-[#172033]'"
  >
    <nav
      class="flex h-[48px] shrink-0 items-end gap-[30px] border-b px-[20px]"
      :class="settingsStore.isDark ? 'border-[rgba(148,163,184,0.16)]' : 'border-[#e5e7eb]'"
      aria-label="任务类型"
    >
      <button
        v-for="tab in tabs"
        :key="tab.value"
        type="button"
        class="relative h-full border-0 bg-transparent px-0 pt-[4px] text-[14px] text-inherit cursor-pointer"
        :class="
          activeTab === tab.value
            ? 'font-600 text-[var(--app-primary-color)]'
            : 'opacity-68 hover:opacity-100'
        "
        @click="activeTab = tab.value"
      >
        {{ tab.label }}
        <span
          v-if="activeTab === tab.value"
          class="absolute inset-x-0 bottom-[-1px] h-[2px] bg-[var(--app-primary-color)]"
        />
      </button>
    </nav>

    <div class="flex shrink-0 flex-wrap items-center gap-[10px] px-[20px] py-[16px]">
      <NButton size="small" secondary :disabled="!hasActiveTasks" @click="cancelAll">
        <template #icon><XCircle :size="15" /></template>
        中断全部
      </NButton>
      <NButton
        size="small"
        secondary
        :disabled="!hasFinishedTasks"
        @click="uploadCenterStore.clearFinished()"
      >
        清除已完成
      </NButton>
      <NButton
        size="small"
        type="error"
        secondary
        :disabled="!uploadCenterStore.hasTasks"
        @click="clearAll"
      >
        <template #icon><Trash2 :size="15" /></template>
        删除全部
      </NButton>
    </div>

    <div class="min-h-0 flex-1 overflow-auto px-[20px] pb-[20px]">
      <div v-if="visibleBatches.length" class="task-table min-w-[640px]">
        <div
          class="task-row task-header"
          :class="settingsStore.isDark ? 'bg-[rgba(148,163,184,0.08)]' : 'bg-[#f7f8fa]'"
        >
          <div>任务名称</div>
          <div>进度</div>
          <div>状态</div>
          <div>类型</div>
          <div aria-label="操作" />
        </div>
        <div
          v-for="batch in visibleBatches"
          :key="batch.id"
          class="task-row border-b"
          :class="settingsStore.isDark ? 'border-[rgba(148,163,184,0.14)]' : 'border-[#e5e7eb]'"
        >
          <div class="flex min-w-0 items-center gap-[11px]" :title="getBatchTitle(batch)">
            <Folder :size="17" class="shrink-0 text-[#e6ad25]" fill="currentColor" />
            <span class="truncate">{{ getBatchTitle(batch) }}</span>
          </div>
          <div class="min-w-0 pr-[12px]">
            <NProgress
              type="line"
              :percentage="getBatchProgress(batch)"
              :show-indicator="false"
              :height="4"
              :processing="isBatchActive(batch)"
            />
            <div class="mt-[4px] flex justify-between gap-[8px] text-[11px] opacity-62">
              <span
                >{{ getStatusLabel(getBatchStatus(batch)) }} {{ getBatchProgress(batch) }}%</span
              >
              <span>{{ getCompletedCount(batch) }}/{{ batch.tasks.length }}</span>
            </div>
          </div>
          <div>
            <NTag size="small" :bordered="false" :type="getStatusType(getBatchStatus(batch))">{{
              getStatusLabel(getBatchStatus(batch))
            }}</NTag>
          </div>
          <div>{{ getSourceLabel(batch.source) }}</div>
          <div class="flex justify-end">
            <NDropdown
              trigger="click"
              :options="getRowOptions(batch)"
              @select="handleRowAction($event, batch)"
            >
              <NButton quaternary circle size="small" aria-label="任务操作"
                ><template #icon><Ellipsis :size="17" /></template
              ></NButton>
            </NDropdown>
          </div>
          <div v-if="batch.errorMessage" class="task-error col-span-full text-[12px] text-red-500">
            {{ batch.errorMessage }}
          </div>
        </div>
      </div>

      <div
        v-else
        class="flex h-full min-h-[220px] flex-col items-center justify-center gap-[10px] opacity-48"
      >
        <Folder :size="34" />
        <span class="text-[13px]">当前没有任务</span>
      </div>
    </div>
  </section>
</template>

<style scoped>
.task-row {
  display: grid;
  grid-template-columns: minmax(200px, 2fr) minmax(190px, 1.2fr) minmax(110px, 0.7fr) minmax(
      88px,
      0.55fr
    ) 40px;
  align-items: center;
  min-height: 56px;
  padding: 8px 14px;
  column-gap: 18px;
  font-size: 13px;
}

.task-header {
  min-height: 40px;
  padding-block: 0;
  font-weight: 600;
}

.task-error {
  padding-left: 28px;
}

@media (max-width: 720px) {
  .task-center nav,
  .task-center > div {
    padding-inline: 14px;
  }
}
</style>
