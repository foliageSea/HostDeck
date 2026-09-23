import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import type { FileTask, FileTaskStatus, FileTaskType } from '@/api/files'
import { getUiApi } from '@/lib/ui'

export type UploadTaskStatus =
  | 'pending'
  | 'processing'
  | 'uploading'
  | 'downloading'
  | 'success'
  | 'error'
  | 'cancelled'
export type UploadTaskSource =
  | 'files'
  | 'files-download'
  | 'docker-image-import'
  | 'docker-image-export'
  | 'files-copy'
  | 'files-move'
  | 'files-delete'
  | 'files-extract'
  | 'files-compress'

export interface UploadTaskItem {
  connectionId: string
  id: string
  loaded: number
  name: string
  path: string
  progress: number
  source: UploadTaskSource
  status: UploadTaskStatus
  total: number
}

export interface UploadBatch {
  connectionId: string
  createdAt: number
  errorMessage: string
  id: string
  path: string
  source: UploadTaskSource
  tasks: UploadTaskItem[]
}

export interface UploadBatchFile {
  file?: File
  name?: string
  path?: string
  size?: number
}

const fileTaskTypeLabels: Record<FileTaskType, string> = {
  compress: '压缩',
  copy: '复制',
  delete: '删除',
  extract: '解压',
  move: '移动',
}

function isFinishedFileTask(status: FileTaskStatus) {
  return status === 'success' || status === 'failed' || status === 'cancelled'
}

function getFileTaskSummary(task: FileTask) {
  return task.items.length === 1 ? task.items[0]?.sourcePath : `${task.items.length} 个项目`
}

export const useUploadCenterStore = defineStore('upload-center', () => {
  const batches = ref<UploadBatch[]>([])
  const batchControllers = new Map<string, AbortController>()
  const cancelledBatchIds = new Set<string>()
  const notifiedRemoteTaskIds = new Set<string>()

  function isTaskActive(status: UploadTaskStatus) {
    return (
      status === 'pending' ||
      status === 'processing' ||
      status === 'uploading' ||
      status === 'downloading'
    )
  }

  const activeTaskCount = computed(() =>
    batches.value.reduce(
      (count, batch) => count + batch.tasks.filter((task) => isTaskActive(task.status)).length,
      0,
    ),
  )

  const totalTaskCount = computed(() =>
    batches.value.reduce((count, batch) => count + batch.tasks.length, 0),
  )

  const hasTasks = computed(() => batches.value.length > 0)

  function createBatch(
    connectionId: string,
    path: string,
    files: Array<File | UploadBatchFile>,
    source: UploadTaskSource = 'files',
  ) {
    const batchId = `upload-batch-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
    const createdAt = Date.now()
    cancelledBatchIds.delete(batchId)
    const tasks = files.map((item, index) => {
      const file = item instanceof File ? item : item.file
      const taskName = item instanceof File ? item.name : (item.name ?? file?.name ?? '未命名任务')
      const taskPath = item instanceof File ? path : (item.path ?? path)
      const taskSize = item instanceof File ? item.size : (item.size ?? file?.size ?? 0)

      return {
        connectionId,
        id: `${batchId}-${index}`,
        loaded: 0,
        name: taskName,
        path: taskPath,
        progress: 0,
        source,
        status: 'pending' as const,
        total: taskSize,
      }
    })

    batches.value.unshift({
      connectionId,
      createdAt,
      errorMessage: '',
      id: batchId,
      path,
      source,
      tasks,
    })

    return batchId
  }

  function findTask(taskId: string) {
    for (const batch of batches.value) {
      const task = batch.tasks.find((item) => item.id === taskId)
      if (task) {
        return task
      }
    }

    return null
  }

  function findBatch(batchId: string) {
    return batches.value.find((item) => item.id === batchId) ?? null
  }

  function updateTask(taskId: string, patch: Partial<UploadTaskItem>) {
    const task = findTask(taskId)
    if (!task) {
      return
    }

    Object.assign(task, patch)
  }

  function notifyRemoteTask(task: FileTask) {
    if (!isFinishedFileTask(task.status) || notifiedRemoteTaskIds.has(task.id)) return

    notifiedRemoteTaskIds.add(task.id)
    const label = fileTaskTypeLabels[task.type]
    const summary = getFileTaskSummary(task)

    if (task.status === 'success') {
      getUiApi().notification.success({
        title: `${label}任务已完成`,
        content: summary,
        duration: 5000,
      })
      return
    }

    if (task.status === 'failed') {
      const itemError = task.items.find((item) => item.errorMessage)?.errorMessage
      getUiApi().notification.error({
        title: `${label}任务失败`,
        content: task.errorMessage || itemError || summary,
        duration: 8000,
      })
      return
    }

    getUiApi().notification.warning({
      title: `${label}任务已取消`,
      content: summary,
      duration: 5000,
    })
  }

  function upsertRemoteTask(task: FileTask, options: { notify?: boolean } = {}) {
    const source = `files-${task.type}` as UploadTaskSource
    const mapStatus = (status: typeof task.status): UploadTaskStatus => {
      if (status === 'queued') return 'pending'
      if (status === 'running') return 'processing'
      if (status === 'failed') return 'error'
      return status
    }
    const batch: UploadBatch = {
      connectionId: task.connectionId,
      createdAt: task.createdAt,
      errorMessage: task.errorMessage ?? '',
      id: task.id,
      path: task.items[0]?.targetPath ?? task.items[0]?.sourcePath ?? '/',
      source,
      tasks: task.items.map((item) => ({
        connectionId: task.connectionId,
        id: `${task.id}-${item.id}`,
        loaded: item.status === 'success' ? 1 : 0,
        name: item.sourcePath,
        path: item.targetPath ?? item.sourcePath,
        progress: item.status === 'success' ? 100 : 0,
        source,
        status: mapStatus(item.status),
        total: 1,
      })),
    }
    const index = batches.value.findIndex((item) => item.id === task.id)
    if (index >= 0) {
      batches.value.splice(index, 1, batch)
    } else {
      batches.value.unshift(batch)
    }

    if (options.notify !== false) notifyRemoteTask(task)
  }

  function markBatchError(batchId: string, message: string) {
    const batch = findBatch(batchId)
    if (!batch) {
      return
    }

    batch.errorMessage = message
  }

  function clearBatchError(batchId: string) {
    const batch = findBatch(batchId)
    if (!batch) {
      return
    }

    batch.errorMessage = ''
  }

  function registerBatchController(batchId: string, controller: AbortController) {
    batchControllers.get(batchId)?.abort()
    cancelledBatchIds.delete(batchId)
    batchControllers.set(batchId, controller)
  }

  function clearBatchController(batchId: string) {
    batchControllers.delete(batchId)
  }

  function isBatchCancelled(batchId: string) {
    return cancelledBatchIds.has(batchId)
  }

  function cancelBatch(batchId: string) {
    const batch = findBatch(batchId)
    if (!batch) {
      return
    }

    if (!batch.tasks.some((task) => isTaskActive(task.status))) {
      return
    }

    cancelledBatchIds.add(batchId)
    batchControllers.get(batchId)?.abort()
    batchControllers.delete(batchId)
    batch.errorMessage =
      batch.source === 'docker-image-export'
        ? '导出已中断。'
        : batch.source === 'files-download'
          ? '下载已中断。'
          : '上传已中断。'

    for (const task of batch.tasks) {
      if (isTaskActive(task.status)) {
        task.status = 'cancelled'
      }
    }
  }

  function removeBatch(batchId: string) {
    const batch = findBatch(batchId)
    if (batch?.tasks.some((task) => isTaskActive(task.status))) {
      cancelBatch(batchId)
    }

    clearBatchController(batchId)
    cancelledBatchIds.delete(batchId)
    batches.value = batches.value.filter((batch) => batch.id !== batchId)
  }

  function clearFinished() {
    batches.value = batches.value.filter((batch) =>
      batch.tasks.some((task) => isTaskActive(task.status)),
    )
  }

  function clearAll() {
    for (const batch of batches.value) {
      if (batch.tasks.some((task) => isTaskActive(task.status))) {
        cancelBatch(batch.id)
      }
    }

    batchControllers.clear()
    cancelledBatchIds.clear()
    batches.value = []
  }

  return {
    activeTaskCount,
    batches,
    cancelBatch,
    clearAll,
    clearBatchError,
    clearBatchController,
    clearFinished,
    createBatch,
    hasTasks,
    isBatchCancelled,
    markBatchError,
    registerBatchController,
    removeBatch,
    totalTaskCount,
    updateTask,
    upsertRemoteTask,
  }
})
