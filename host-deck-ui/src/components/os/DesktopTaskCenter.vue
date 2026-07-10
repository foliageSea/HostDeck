<script setup lang="ts">
import { computed } from 'vue'
import { Close, CloudUpload, Download, StopFilledAlt } from '@vicons/carbon'
import { useSettingsStore } from '@/stores/settings'
import {
  useUploadCenterStore,
  type UploadBatch,
  type UploadTaskSource,
  type UploadTaskStatus,
} from '@/stores/upload-center'

const settingsStore = useSettingsStore()
const uploadCenterStore = useUploadCenterStore()

const hasUnreadUploads = computed(() => uploadCenterStore.activeTaskCount > 0)
const hasActiveDownloads = computed(() =>
  uploadCenterStore.batches.some((batch) =>
    batch.tasks.some((task) => task.status === 'downloading'),
  ),
)
const uploadBatches = computed(() =>
  uploadCenterStore.batches.map((batch) => {
    const totalBytes = batch.tasks.reduce((sum, task) => sum + task.total, 0)
    const loadedBytes = batch.tasks.reduce((sum, task) => sum + task.loaded, 0)
    const completedCount = batch.tasks.filter((task) => task.status === 'success').length
    const cancelledCount = batch.tasks.filter((task) => task.status === 'cancelled').length
    const failedCount = batch.tasks.filter((task) => task.status === 'error').length
    const activeTask = batch.tasks.find(
      (task) => task.status === 'uploading' || task.status === 'downloading',
    )

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

function formatUploadStatus(status: UploadTaskStatus, source: UploadTaskSource) {
  if (status === 'uploading') {
    if (source === 'docker-image-import') {
      return '导入中'
    }

    return '上传中'
  }

  if (status === 'downloading') {
    if (source === 'docker-image-export') {
      return '导出中'
    }

    return '下载中'
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

function getTaskSourceTitle(source: UploadTaskSource) {
  if (source === 'files-download') {
    return '文件下载'
  }

  if (source === 'docker-image-import') {
    return '镜像导入'
  }

  if (source === 'docker-image-export') {
    return '镜像导出'
  }

  return '文件上传'
}

function getTaskActiveText(source: UploadTaskSource, name: string) {
  if (source === 'files-download') {
    return `正在下载 ${name}`
  }

  if (source === 'docker-image-import') {
    return `正在导入 ${name}`
  }

  if (source === 'docker-image-export') {
    return `正在导出 ${name}`
  }

  return `正在上传 ${name}`
}

function getCancelTaskText(source: UploadTaskSource) {
  if (source === 'files-download') {
    return '中断下载'
  }

  if (source === 'docker-image-import') {
    return '中断导入'
  }

  if (source === 'docker-image-export') {
    return '中断导出'
  }

  return '中断上传'
}

function formatBatchTime(timestamp: number) {
  return new Intl.DateTimeFormat('zh-CN', {
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    month: '2-digit',
  }).format(new Date(timestamp))
}

function isBatchActive(batch: UploadBatch) {
  return batch.tasks.some(
    (task) =>
      task.status === 'pending' || task.status === 'uploading' || task.status === 'downloading',
  )
}

function cancelUploadBatch(batchId: string) {
  uploadCenterStore.cancelBatch(batchId)
}

function handleTaskCenterVisibilityChange(value: boolean) {
  uploadCenterStore.panelOpen = value
}
</script>

<template>
  <NPopover
    trigger="click"
    placement="bottom-end"
    :show="uploadCenterStore.panelOpen"
    @update:show="handleTaskCenterVisibilityChange"
  >
    <template #trigger>
      <NBadge
        :value="uploadCenterStore.activeTaskCount"
        :show="hasUnreadUploads"
        :max="99"
        :offset="[-4, 6]"
        :color="settingsStore.primaryColor"
        processing
      >
        <NButton quaternary circle>
          <template #icon>
            <NIcon :size="16">
              <component :is="hasActiveDownloads ? Download : CloudUpload" />
            </NIcon>
          </template>
        </NButton>
      </NBadge>
    </template>

    <div
      class="app-radius-card flex max-h-[min(72vh,720px)] w-[min(460px,calc(100vw_-_24px))] flex-col gap-[14px] rounded-[18px] p-[14px] backdrop-blur-[18px] lt-md:max-h-[68vh] lt-md:w-[min(420px,calc(100vw_-_16px))]"
    >
      <div class="flex items-start justify-between gap-[12px]">
        <div>
          <div class="text-[14px] font-700">任务中心</div>
          <div
            class="text-[12px]"
            :class="
              settingsStore.isDark
                ? 'text-[rgba(148,163,184,0.94)]'
                : 'text-[rgba(100,116,139,0.92)]'
            "
          >
            {{ uploadCenterStore.totalTaskCount }} 个任务
            <template v-if="uploadCenterStore.activeTaskCount > 0">
              ，{{ uploadCenterStore.activeTaskCount }} 个进行中
            </template>
          </div>
        </div>
        <div class="flex items-center gap-[8px]">
          <NButton
            quaternary
            size="small"
            :disabled="!uploadCenterStore.hasTasks"
            @click="uploadCenterStore.clearFinished()"
          >
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

      <div
        v-if="uploadBatches.length === 0"
        class="text-[12px]"
        :class="
          settingsStore.isDark ? 'text-[rgba(148,163,184,0.94)]' : 'text-[rgba(100,116,139,0.92)]'
        "
      >
        当前没有任务
      </div>

      <div v-else class="flex flex-col gap-[12px] overflow-auto pr-[2px]">
        <div
          v-for="batch in uploadBatches"
          :key="batch.id"
          class="app-radius-surface flex flex-col gap-[10px] rounded-[16px] p-[12px]"
          :class="[
            settingsStore.isDark
              ? 'border border-[rgba(148,163,184,0.16)] bg-[rgba(30,41,59,0.52)]'
              : 'border border-[rgba(148,163,184,0.2)] bg-[linear-gradient(180deg,rgba(248,250,252,0.98),rgba(241,245,249,0.98))]',
            isBatchActive(batch)
              ? settingsStore.isDark
                ? 'border-[rgba(96,165,250,0.34)]'
                : 'border-[rgba(59,130,246,0.32)] shadow-[inset_0_0_0_1px_rgba(191,219,254,0.7)]'
              : '',
          ]"
        >
          <div class="flex items-start justify-between gap-[12px] lt-md:flex-col">
            <div class="min-w-0 flex-1">
              <div
                class="truncate-line text-[13px] font-600"
                :class="settingsStore.isDark ? '' : 'text-[#0f172a]'"
              >
                {{ getTaskSourceTitle(batch.source) }} · {{ batch.path }}
              </div>
              <div
                class="truncate-line text-[12px]"
                :class="
                  settingsStore.isDark
                    ? 'text-[rgba(148,163,184,0.94)]'
                    : 'text-[rgba(100,116,139,0.92)]'
                "
              >
                {{ formatBatchTime(batch.createdAt) }}
                <template v-if="batch.currentFileName">
                  · {{ getTaskActiveText(batch.source, batch.currentFileName) }}
                </template>
                · {{ batch.completedCount }}/{{ batch.totalCount }} 完成
                <template v-if="batch.cancelledCount > 0">
                  · {{ batch.cancelledCount }} 已中断
                </template>
                <template v-if="batch.failedCount > 0"> · {{ batch.failedCount }} 失败 </template>
              </div>
            </div>
            <div class="flex flex-col items-end gap-[8px] lt-md:items-start">
              <div
                class="flex flex-col items-end gap-[4px] text-[12px] lt-md:items-start"
                :class="
                  settingsStore.isDark
                    ? 'text-[rgba(191,219,254,0.96)]'
                    : 'text-[rgba(37,99,235,0.86)]'
                "
              >
                <span>{{ batch.progress }}%</span>
                <span
                  >{{ formatFileSize(batch.loadedBytes) }} /
                  {{ formatFileSize(batch.totalBytes) }}</span
                >
              </div>
              <NButton
                v-if="isBatchActive(batch)"
                quaternary
                size="tiny"
                @click="cancelUploadBatch(batch.id)"
              >
                <template #icon>
                  <NIcon :size="14">
                    <StopFilledAlt />
                  </NIcon>
                </template>
                {{ getCancelTaskText(batch.source) }}
              </NButton>
            </div>
          </div>

          <NProgress
            type="line"
            :percentage="batch.progress"
            :show-indicator="false"
            :processing="isBatchActive(batch)"
          />

          <div
            v-if="batch.errorMessage"
            class="text-[12px]"
            :class="
              settingsStore.isDark ? 'text-[rgba(248,113,113,0.96)]' : 'text-[rgba(220,38,38,0.92)]'
            "
          >
            {{ batch.errorMessage }}
          </div>

          <div class="flex flex-col gap-[8px]">
            <div
              v-for="task in batch.tasks"
              :key="task.id"
              class="app-radius-item flex flex-col gap-[8px] rounded-[12px] p-[10px]"
              :class="[
                settingsStore.isDark
                  ? 'border border-[rgba(148,163,184,0.12)] bg-[rgba(15,23,42,0.52)]'
                  : 'border border-[rgba(148,163,184,0.18)] bg-[rgba(255,255,255,0.98)]',
                task.status === 'uploading' || task.status === 'downloading'
                  ? settingsStore.isDark
                    ? 'border-[rgba(96,165,250,0.28)]'
                    : 'border-[rgba(59,130,246,0.28)]'
                  : '',
                task.status === 'success'
                  ? settingsStore.isDark
                    ? 'border-[rgba(74,222,128,0.24)]'
                    : 'border-[rgba(34,197,94,0.24)]'
                  : '',
                task.status === 'error'
                  ? settingsStore.isDark
                    ? 'border-[rgba(248,113,113,0.28)]'
                    : 'border-[rgba(239,68,68,0.24)]'
                  : '',
              ]"
            >
              <div class="flex items-start justify-between gap-[12px] lt-md:flex-col">
                <div
                  class="truncate-line flex-1"
                  :class="settingsStore.isDark ? '' : 'text-[#0f172a]'"
                  :title="task.name"
                >
                  {{ task.name }}
                </div>
                <NTag
                  class="shrink-0"
                  size="small"
                  :type="
                    task.status === 'error'
                      ? 'error'
                      : task.status === 'success'
                        ? 'success'
                        : task.status === 'cancelled'
                          ? 'warning'
                          : 'info'
                  "
                >
                  {{ formatUploadStatus(task.status, task.source) }}
                </NTag>
              </div>
              <div
                class="flex items-start justify-between gap-[12px] text-[12px] lt-md:flex-col"
                :class="
                  settingsStore.isDark
                    ? 'text-[rgba(148,163,184,0.94)]'
                    : 'text-[rgba(100,116,139,0.92)]'
                "
              >
                <span>{{ formatFileSize(task.loaded) }} / {{ formatFileSize(task.total) }}</span>
                <span>{{ task.progress }}%</span>
              </div>
              <NProgress
                type="line"
                :percentage="task.progress"
                :status="
                  task.status === 'error'
                    ? 'error'
                    : task.status === 'success'
                      ? 'success'
                      : task.status === 'cancelled'
                        ? 'warning'
                        : 'default'
                "
                :show-indicator="false"
                :processing="task.status === 'uploading' || task.status === 'downloading'"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  </NPopover>
</template>
