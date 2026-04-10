import { computed, ref } from 'vue'
import { defineStore } from 'pinia'

export type UploadTaskStatus = 'pending' | 'uploading' | 'success' | 'error'

export interface UploadTaskItem {
  id: string
  loaded: number
  name: string
  path: string
  progress: number
  sessionId: string
  source: 'files'
  status: UploadTaskStatus
  total: number
}

export interface UploadBatch {
  createdAt: number
  errorMessage: string
  id: string
  path: string
  sessionId: string
  source: 'files'
  tasks: UploadTaskItem[]
}

export const useUploadCenterStore = defineStore('upload-center', () => {
  const batches = ref<UploadBatch[]>([])
  const panelOpen = ref(false)

  const activeTaskCount = computed(() =>
    batches.value.reduce(
      (count, batch) => count + batch.tasks.filter((task) => task.status === 'pending' || task.status === 'uploading').length,
      0,
    ),
  )

  const totalTaskCount = computed(() =>
    batches.value.reduce((count, batch) => count + batch.tasks.length, 0),
  )

  const hasTasks = computed(() => batches.value.length > 0)

  function createBatch(sessionId: string, path: string, files: File[]) {
    const batchId = `upload-batch-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
    const createdAt = Date.now()
    const tasks = files.map((file, index) => ({
      id: `${batchId}-${index}`,
      loaded: 0,
      name: file.name,
      path,
      progress: 0,
      sessionId,
      source: 'files' as const,
      status: 'pending' as const,
      total: file.size,
    }))

    batches.value.unshift({
      createdAt,
      errorMessage: '',
      id: batchId,
      path,
      sessionId,
      source: 'files',
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

  function updateTask(taskId: string, patch: Partial<UploadTaskItem>) {
    const task = findTask(taskId)
    if (!task) {
      return
    }

    Object.assign(task, patch)
  }

  function markBatchError(batchId: string, message: string) {
    const batch = batches.value.find((item) => item.id === batchId)
    if (!batch) {
      return
    }

    batch.errorMessage = message
    panelOpen.value = true
  }

  function clearBatchError(batchId: string) {
    const batch = batches.value.find((item) => item.id === batchId)
    if (!batch) {
      return
    }

    batch.errorMessage = ''
  }

  function removeBatch(batchId: string) {
    batches.value = batches.value.filter((batch) => batch.id !== batchId)
  }

  function clearFinished() {
    batches.value = batches.value.filter((batch) =>
      batch.tasks.some((task) => task.status === 'pending' || task.status === 'uploading'),
    )
  }

  function clearAll() {
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
    clearAll,
    clearBatchError,
    clearFinished,
    closePanel,
    createBatch,
    hasTasks,
    markBatchError,
    openPanel,
    panelOpen,
    removeBatch,
    togglePanel,
    totalTaskCount,
    updateTask,
  }
})
