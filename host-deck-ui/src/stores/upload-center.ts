import { computed, onScopeDispose, ref } from 'vue'
import { defineStore } from 'pinia'
import { filesApi, type FileTask, type FileTaskStatus, type FileTaskType } from '@/api/files'
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
  progress: number | null
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
  remoteTask?: FileTask
  remoteTaskWindowId?: string
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

export function getRemoteTaskStatus(status: FileTaskStatus): UploadTaskStatus {
  if (status === 'queued') return 'pending'
  if (status === 'running') return 'processing'
  if (status === 'failed') return 'error'
  return status
}

function getFileTaskSummary(task: FileTask) {
  return task.items.length === 1 ? task.items[0]?.sourcePath : `${task.items.length} 个项目`
}

function getRemoteTaskError(task: FileTask) {
  return (
    task.items.find((item) => item.status === 'failed' && item.errorMessage)?.errorMessage ||
    task.items.find((item) => item.errorMessage)?.errorMessage ||
    task.errorMessage ||
    ''
  )
}

interface RemoteTaskWatch {
  controller?: AbortController
  retryTimer?: ReturnType<typeof setTimeout>
  retryDelay: number
}

const initialRetryDelay = 1000
const maxRetryDelay = 30_000

export function isBatchActive(batch: UploadBatch) {
  if (batch.remoteTask) return !isFinishedFileTask(batch.remoteTask.status)
  return batch.tasks.some((task) => isTaskActive(task.status))
}

function isTaskActive(status: UploadTaskStatus) {
  return (
    status === 'pending' ||
    status === 'processing' ||
    status === 'uploading' ||
    status === 'downloading'
  )
}

export const useUploadCenterStore = defineStore('upload-center', () => {
  const batches = ref<UploadBatch[]>([])
  const batchControllers = new Map<string, AbortController>()
  const cancelledBatchIds = new Set<string>()
  const dismissedRemoteTaskIds = new Set<string>()
  const remoteTaskWatches = new Map<string, RemoteTaskWatch>()
  const remoteTaskCancellations = new Set<string>()
  const remoteTaskCompletionListeners = new Set<(task: FileTask, windowId?: string) => void>()
  let remoteTaskClearGeneration = 0
  let disposed = false

  function onRemoteTaskCompleted(listener: (task: FileTask, windowId?: string) => void) {
    remoteTaskCompletionListeners.add(listener)
    return () => {
      remoteTaskCompletionListeners.delete(listener)
    }
  }

  onScopeDispose(() => {
    disposed = true
    for (const taskId of remoteTaskWatches.keys()) stopWatchingRemoteTask(taskId)
    remoteTaskCompletionListeners.clear()
  })

  const activeTaskCount = computed(() =>
    batches.value.reduce((count, batch) => {
      if (batch.remoteTask && !isBatchActive(batch)) return count
      const activeItems = batch.tasks.filter((task) => isTaskActive(task.status)).length
      return count + (batch.remoteTask ? Math.max(1, activeItems) : activeItems)
    }, 0),
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
      getUiApi().notification.error({
        title: `${label}任务失败`,
        content: getRemoteTaskError(task) || summary,
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

  function upsertRemoteTask(
    task: FileTask,
    options: { notify?: boolean; snapshot?: boolean; windowId?: string } = {},
  ) {
    if (disposed || dismissedRemoteTaskIds.has(task.id)) return

    const existingBatch = findBatch(task.id)
    const previous = existingBatch?.remoteTask
    const finished = isFinishedFileTask(task.status)
    // History and cancel responses can race the stream. An observed terminal task is immutable,
    // and an active HTTP snapshot must not overwrite the live progress already in the store.
    if (previous && isFinishedFileTask(previous.status)) return
    if (previous && !finished) {
      if (options.windowId && existingBatch) existingBatch.remoteTaskWindowId = options.windowId
      if (options.snapshot) return
      if (previous.status === 'running' && task.status === 'queued') return
    }

    const source: UploadTaskSource = `files-${task.type}`
    const batch: UploadBatch = {
      connectionId: task.connectionId,
      createdAt: task.createdAt,
      errorMessage: getRemoteTaskError(task),
      id: task.id,
      path: task.items[0]?.targetPath ?? task.items[0]?.sourcePath ?? '/',
      source,
      remoteTask: task,
      remoteTaskWindowId: options.windowId ?? existingBatch?.remoteTaskWindowId,
      tasks: task.items.map((item) => ({
        connectionId: task.connectionId,
        id: `${task.id}-${item.id}`,
        loaded: 0,
        name: item.sourcePath,
        path: item.targetPath ?? item.sourcePath,
        progress: null,
        source,
        status: getRemoteTaskStatus(item.status),
        total: 0,
      })),
    }
    const index = batches.value.findIndex((item) => item.id === task.id)
    if (index >= 0) {
      batches.value.splice(index, 1, batch)
    } else {
      batches.value.unshift(batch)
    }

    if (!finished) {
      watchRemoteTask(task.id)
      return
    }

    stopWatchingRemoteTask(task.id)
    // A terminal entry first discovered in history is silent. A known active task completing
    // during that same request still needs its usual notification and file refresh.
    if (previous || options.notify !== false) {
      notifyRemoteTask(task)
      for (const listener of remoteTaskCompletionListeners) listener(task, batch.remoteTaskWindowId)
    }
  }

  function stopWatchingRemoteTask(taskId: string) {
    const watch = remoteTaskWatches.get(taskId)
    if (!watch) return

    remoteTaskWatches.delete(taskId)
    clearTimeout(watch.retryTimer)
    watch.controller?.abort()
  }

  function watchRemoteTask(taskId: string) {
    if (remoteTaskWatches.has(taskId)) return
    const watch: RemoteTaskWatch = { retryDelay: initialRetryDelay }
    remoteTaskWatches.set(taskId, watch)

    async function connect() {
      const controller = new AbortController()
      const connectedAt = Date.now()
      watch.retryTimer = undefined
      watch.controller = controller
      try {
        await filesApi.watchTask(
          taskId,
          (nextTask) => {
            if (
              watch.controller === controller &&
              !controller.signal.aborted &&
              nextTask.id === taskId
            ) {
              upsertRemoteTask(nextTask)
            }
          },
          controller.signal,
        )
      } catch {
        // Both a transport error and EOF without a terminal event reconnect.
      }
      if (remoteTaskWatches.get(taskId) !== watch) return

      watch.controller = undefined
      // Replaying the initial snapshot on a short-lived reconnect doesn't reset backoff.
      if (Date.now() - connectedAt >= maxRetryDelay) watch.retryDelay = initialRetryDelay
      watch.retryTimer = setTimeout(() => void connect(), watch.retryDelay)
      watch.retryDelay = Math.min(watch.retryDelay * 2, maxRetryDelay)
    }

    void connect()
  }

  async function restoreRemoteTasks(connectionId: string) {
    const generation = remoteTaskClearGeneration
    const tasks = await filesApi.listTasks(connectionId)
    if (generation !== remoteTaskClearGeneration) return
    for (const task of tasks) upsertRemoteTask(task, { notify: false, snapshot: true })
  }

  async function cancelRemoteTask(taskId: string) {
    if (remoteTaskCancellations.has(taskId)) return
    remoteTaskCancellations.add(taskId)
    try {
      const task = await filesApi.cancelTask(taskId)
      upsertRemoteTask(task, { snapshot: true })
    } catch {
      if (!disposed) getUiApi().message.error('中断文件任务失败。')
    } finally {
      remoteTaskCancellations.delete(taskId)
    }
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

    if (!isBatchActive(batch)) return
    if (batch.remoteTask) {
      void cancelRemoteTask(batchId)
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
    if (batch && isBatchActive(batch)) cancelBatch(batchId)
    if (batch?.remoteTask) {
      dismissedRemoteTaskIds.add(batchId)
      stopWatchingRemoteTask(batchId)
    }

    clearBatchController(batchId)
    cancelledBatchIds.delete(batchId)
    batches.value = batches.value.filter((batch) => batch.id !== batchId)
  }

  function clearFinished() {
    for (const batch of batches.value) {
      if (batch.remoteTask && !isBatchActive(batch)) dismissedRemoteTaskIds.add(batch.id)
    }
    batches.value = batches.value.filter(isBatchActive)
  }

  function clearAll() {
    remoteTaskClearGeneration++
    for (const batch of batches.value) {
      if (isBatchActive(batch)) cancelBatch(batch.id)
      if (batch.remoteTask) {
        dismissedRemoteTaskIds.add(batch.id)
        stopWatchingRemoteTask(batch.id)
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
    onRemoteTaskCompleted,
    registerBatchController,
    removeBatch,
    restoreRemoteTasks,
    totalTaskCount,
    updateTask,
    upsertRemoteTask,
  }
})
