import { computed, ref } from 'vue'
import { defineStore } from 'pinia'

export type UploadTaskStatus = 'pending' | 'uploading' | 'downloading' | 'success' | 'error' | 'cancelled'
export type UploadTaskSource = 'files' | 'files-download' | 'docker-image-import'

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

export const useUploadCenterStore = defineStore('upload-center', () => {
  const batches = ref<UploadBatch[]>([])
  const panelOpen = ref(false)
  const batchControllers = new Map<string, AbortController>()
  const cancelledBatchIds = new Set<string>()

  function isTaskActive(status: UploadTaskStatus) {
    return status === 'pending' || status === 'uploading' || status === 'downloading'
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

    panelOpen.value = true
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

  function markBatchError(batchId: string, message: string) {
    const batch = findBatch(batchId)
    if (!batch) {
      return
    }

    batch.errorMessage = message
    panelOpen.value = true
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
    batch.errorMessage = batch.source === 'files-download' ? '下载已中断。' : '上传已中断。'

    for (const task of batch.tasks) {
      if (isTaskActive(task.status)) {
        task.status = 'cancelled'
      }
    }

    panelOpen.value = true
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

  function openPanel() {
    panelOpen.value = true
  }

  function closePanel() {
    panelOpen.value = false
  }

  function togglePanel() {
    panelOpen.value = !panelOpen.value
  }

  return {
    activeTaskCount,
    batches,
    cancelBatch,
    clearAll,
    clearBatchError,
    clearBatchController,
    clearFinished,
    closePanel,
    createBatch,
    hasTasks,
    isBatchCancelled,
    markBatchError,
    openPanel,
    panelOpen,
    registerBatchController,
    removeBatch,
    togglePanel,
    totalTaskCount,
    updateTask,
  }
})
