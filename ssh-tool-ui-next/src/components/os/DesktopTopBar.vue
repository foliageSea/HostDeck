<script setup lang="ts">
import { computed } from 'vue'
import { Close, Logout, Moon, Notification, Sun } from '@vicons/carbon'
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
const hasUnreadUploads = computed(() => uploadCenterStore.activeTaskCount > 0)
const uploadBatches = computed(() =>
  uploadCenterStore.batches.map((batch) => {
    const totalBytes = batch.tasks.reduce((sum, task) => sum + task.total, 0)
    const loadedBytes = batch.tasks.reduce((sum, task) => sum + task.loaded, 0)
    const completedCount = batch.tasks.filter((task) => task.status === 'success').length
    const failedCount = batch.tasks.filter((task) => task.status === 'error').length
    const activeTask = batch.tasks.find((task) => task.status === 'uploading')

    return {
      ...batch,
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

function isBatchActive(batch: UploadBatch) {
  return batch.tasks.some((task) => task.status === 'pending' || task.status === 'uploading')
}

function handleTaskCenterVisibilityChange(value: boolean) {
  uploadCenterStore.panelOpen = value
}

function disconnect() {
  getUiApi().dialog.warning({
    title: '断开连接',
    content: '确认结束当前 SSH 会话并返回登录页？',
    positiveText: '断开',
    negativeText: '取消',
    onPositiveClick: () => {
      desktopStore.reset()
      sshStore.clearSession()
    },
  })
}
</script>

<template>
  <header class="desktop-topbar" :class="{ 'desktop-topbar-light': !settingsStore.isDark }">
    <div class="desktop-topbar-section">
      <span class="topbar-brand">SSH Tool</span>
    </div>

    <div class="desktop-topbar-section desktop-topbar-center">
      <span>{{ sshStore.host || '未连接主机' }}</span>
    </div>

    <div class="desktop-topbar-section">
      <NPopover
        trigger="click"
        placement="bottom-end"
        :show="uploadCenterStore.panelOpen"
        @update:show="handleTaskCenterVisibilityChange"
      >
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

        <div class="upload-center-panel" :class="{ 'upload-center-panel-light': !settingsStore.isDark }">
          <div class="upload-center-header">
            <div>
              <div class="upload-center-title">任务中心</div>
              <div class="upload-center-meta">
                {{ uploadCenterStore.totalTaskCount }} 个上传任务
                <template v-if="uploadCenterStore.activeTaskCount > 0">
                  ，{{ uploadCenterStore.activeTaskCount }} 个进行中
                </template>
              </div>
            </div>
            <div class="upload-center-actions">
              <NButton quaternary size="small" :disabled="!uploadCenterStore.hasTasks" @click="uploadCenterStore.clearFinished()">
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

          <div v-if="uploadBatches.length === 0" class="upload-center-empty">
            当前没有上传任务
          </div>

          <div v-else class="upload-center-list">
            <div
              v-for="batch in uploadBatches"
              :key="batch.id"
              class="upload-center-batch"
              :class="{ 'upload-center-batch-active': isBatchActive(batch) }"
            >
              <div class="upload-center-batch-header">
                <div>
                  <div class="upload-center-batch-title">文件上传 · {{ batch.path }}</div>
                  <div class="upload-center-batch-meta">
                    {{ formatBatchTime(batch.createdAt) }}
                    <template v-if="batch.currentFileName">
                      · 正在上传 {{ batch.currentFileName }}
                    </template>
                    · {{ batch.completedCount }}/{{ batch.totalCount }} 完成
                    <template v-if="batch.failedCount > 0">
                      · {{ batch.failedCount }} 失败
                    </template>
                  </div>
                </div>
                <div class="upload-center-batch-progress">
                  <span>{{ batch.progress }}%</span>
                  <span>{{ formatFileSize(batch.loadedBytes) }} / {{ formatFileSize(batch.totalBytes) }}</span>
                </div>
              </div>

              <NProgress
                type="line"
                :percentage="batch.progress"
                :show-indicator="false"
                :processing="isBatchActive(batch)"
              />

              <div v-if="batch.errorMessage" class="upload-center-error">
                {{ batch.errorMessage }}
              </div>

              <div class="upload-center-task-list">
                <div
                  v-for="task in batch.tasks"
                  :key="task.id"
                  class="upload-center-task"
                  :class="[`upload-center-task-${task.status}`]"
                >
                  <div class="upload-center-task-header">
                    <div class="upload-center-task-name" :title="task.name">{{ task.name }}</div>
                    <NTag size="small" :type="task.status === 'error' ? 'error' : task.status === 'success' ? 'success' : 'info'">
                      {{ formatUploadStatus(task.status) }}
                    </NTag>
                  </div>
                  <div class="upload-center-task-meta">
                    <span>{{ formatFileSize(task.loaded) }} / {{ formatFileSize(task.total) }}</span>
                    <span>{{ task.progress }}%</span>
                  </div>
                  <NProgress
                    type="line"
                    :percentage="task.progress"
                    :status="task.status === 'error' ? 'error' : task.status === 'success' ? 'success' : 'default'"
                    :show-indicator="false"
                    :processing="task.status === 'uploading'"
                  />
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

<style scoped>
.desktop-topbar {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 48px;
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
  padding: 0 16px;
  background: rgba(15, 23, 42, 0.45);
  border-bottom: 1px solid rgba(148, 163, 184, 0.16);
  backdrop-filter: blur(16px);
  z-index: 20;
}

.desktop-topbar-section {
  display: flex;
  align-items: center;
  gap: 12px;
  color: #e2e8f0;
  min-width: 0;
}

.desktop-topbar-center {
  justify-content: center;
  font-size: 0.92rem;
  color: rgba(226, 232, 240, 0.8);
}

.desktop-topbar-section:last-child {
  justify-content: flex-end;
}

.upload-center-panel {
  width: min(460px, calc(100vw - 24px));
  max-height: min(72vh, 720px);
  display: flex;
  flex-direction: column;
  gap: 14px;
  padding: 14px;
  border: 1px solid rgba(148, 163, 184, 0.18);
  border-radius: 18px;
  background: rgba(15, 23, 42, 0.92);
  color: #e2e8f0;
  backdrop-filter: blur(18px);
  box-shadow: 0 18px 48px rgba(15, 23, 42, 0.28);
}

.upload-center-header,
.upload-center-batch-header,
.upload-center-task-header,
.upload-center-task-meta {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}

.upload-center-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.upload-center-title {
  font-size: 14px;
  font-weight: 700;
}

.upload-center-meta,
.upload-center-batch-meta,
.upload-center-task-meta,
.upload-center-empty,
.upload-center-error {
  font-size: 12px;
  color: rgba(148, 163, 184, 0.94);
}

.upload-center-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
  overflow: auto;
  padding-right: 2px;
}

.upload-center-batch {
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 12px;
  border-radius: 16px;
  border: 1px solid rgba(148, 163, 184, 0.16);
  background: rgba(30, 41, 59, 0.52);
}

.upload-center-batch-active {
  border-color: rgba(96, 165, 250, 0.34);
}

.upload-center-batch-title,
.upload-center-task-name {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.upload-center-batch-title {
  font-size: 13px;
  font-weight: 600;
}

.upload-center-batch-progress {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 4px;
  font-size: 12px;
  color: rgba(191, 219, 254, 0.96);
}

.upload-center-task-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.upload-center-task {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 10px;
  border-radius: 12px;
  border: 1px solid rgba(148, 163, 184, 0.12);
  background: rgba(15, 23, 42, 0.52);
}

.upload-center-task-uploading {
  border-color: rgba(96, 165, 250, 0.28);
}

.upload-center-task-success {
  border-color: rgba(74, 222, 128, 0.24);
}

.upload-center-task-error {
  border-color: rgba(248, 113, 113, 0.28);
}

.upload-center-error {
  color: rgba(248, 113, 113, 0.96);
}

.topbar-brand {
  font-weight: 700;
  letter-spacing: 0.04em;
}

.desktop-topbar-light {
  background: rgba(255, 255, 255, 0.58);
  border-bottom-color: rgba(148, 163, 184, 0.22);
}

.desktop-topbar-light .desktop-topbar-section {
  color: #1e293b;
}

.desktop-topbar-light .desktop-topbar-center {
  color: rgba(51, 65, 85, 0.82);
}

.upload-center-panel-light {
  background: rgba(255, 255, 255, 0.96);
  border-color: rgba(148, 163, 184, 0.24);
  color: #0f172a;
  box-shadow: 0 18px 42px rgba(148, 163, 184, 0.24);
}

.upload-center-panel-light .upload-center-meta,
.upload-center-panel-light .upload-center-batch-meta,
.upload-center-panel-light .upload-center-task-meta,
.upload-center-panel-light .upload-center-empty {
  color: rgba(100, 116, 139, 0.92);
}

.upload-center-panel-light .upload-center-batch {
  background: linear-gradient(180deg, rgba(248, 250, 252, 0.98), rgba(241, 245, 249, 0.98));
  border-color: rgba(148, 163, 184, 0.2);
}

.upload-center-panel-light .upload-center-batch-active {
  border-color: rgba(59, 130, 246, 0.32);
  box-shadow: inset 0 0 0 1px rgba(191, 219, 254, 0.7);
}

.upload-center-panel-light .upload-center-task {
  background: rgba(255, 255, 255, 0.98);
  border-color: rgba(148, 163, 184, 0.18);
}

.upload-center-panel-light .upload-center-task-uploading {
  border-color: rgba(59, 130, 246, 0.28);
}

.upload-center-panel-light .upload-center-task-success {
  border-color: rgba(34, 197, 94, 0.24);
}

.upload-center-panel-light .upload-center-task-error {
  border-color: rgba(239, 68, 68, 0.24);
}

.upload-center-panel-light .upload-center-batch-title,
.upload-center-panel-light .upload-center-task-name,
.upload-center-panel-light .upload-center-title {
  color: #0f172a;
}

.upload-center-panel-light .upload-center-batch-progress {
  color: rgba(37, 99, 235, 0.86);
}

.upload-center-panel-light .upload-center-error {
  color: rgba(220, 38, 38, 0.92);
}

@media (max-width: 768px) {
  .upload-center-panel {
    width: min(420px, calc(100vw - 16px));
    max-height: 68vh;
  }

  .upload-center-batch-header,
  .upload-center-task-header,
  .upload-center-task-meta {
    flex-direction: column;
    align-items: flex-start;
  }

  .upload-center-batch-progress {
    align-items: flex-start;
  }
}
</style>
