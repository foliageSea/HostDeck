import { computed, ref } from 'vue'
import { filesApi } from '@/api/files'
import { getUiApi } from '@/lib/ui'
import { useUploadCenterStore } from '@/stores/upload-center'
import { resolve } from '@/utils/path'
import {
  getUploadDirectory,
  getUploadFilename,
  getUploadRelativePath,
  isTransferCancelled,
} from '../utils/transfer'

interface UploadSelection {
  file: File
  name: string
  path: string
  relativePath: string
}

interface DroppedFileEntry {
  isDirectory: false
  isFile: true
  name: string
  file: (success: (file: File) => void, error?: (error: DOMException) => void) => void
}

interface DroppedDirectoryReader {
  readEntries: (
    success: (entries: DroppedEntry[]) => void,
    error?: (error: DOMException) => void,
  ) => void
}

interface DroppedDirectoryEntry {
  isDirectory: true
  isFile: false
  name: string
  createReader: () => DroppedDirectoryReader
}

type DroppedEntry = DroppedFileEntry | DroppedDirectoryEntry

export interface UseFileUploadsOptions {
  getConnectionId: () => string | null
  getCurrentPath: () => string
  refreshFiles: () => Promise<unknown>
}

export function useFileUploads({
  getConnectionId,
  getCurrentPath,
  refreshFiles,
}: UseFileUploadsOptions) {
  const uploadCenterStore = useUploadCenterStore()
  const fileInputRef = ref<HTMLInputElement | null>(null)
  const directoryInputRef = ref<HTMLInputElement | null>(null)
  const dragDepth = ref(0)
  const isDraggingUpload = ref(false)
  const isUploading = computed(() => uploadCenterStore.activeTaskCount > 0)

  function triggerUpload() {
    if (isUploading.value) {
      return
    }

    fileInputRef.value?.click()
  }

  function triggerDirectoryUpload() {
    if (isUploading.value) {
      return
    }

    directoryInputRef.value?.click()
  }

  async function ensureUploadDirectories(connectionId: string, relativePaths: string[]) {
    const directories = Array.from(
      new Set(relativePaths.map(getUploadDirectory).filter(Boolean)),
    ).sort((left, right) => left.split('/').length - right.split('/').length)

    for (const directory of directories) {
      try {
        await filesApi.mkdir(connectionId, resolve(getCurrentPath(), directory))
      } catch {
        // Existing remote directories are fine; upload will still fail later if the path is unusable.
      }
    }
  }

  function isFileDrag(event: DragEvent) {
    return Array.from(event.dataTransfer?.types ?? []).includes('Files')
  }

  function handleUploadDragEnter(event: DragEvent) {
    if (!isFileDrag(event)) {
      return
    }

    dragDepth.value += 1
    isDraggingUpload.value = true
  }

  function handleUploadDragLeave() {
    if (!isDraggingUpload.value) {
      return
    }

    dragDepth.value = Math.max(0, dragDepth.value - 1)
    if (dragDepth.value === 0) {
      isDraggingUpload.value = false
    }
  }

  function readDroppedFile(entry: DroppedFileEntry) {
    return new Promise<File>((resolveFile, reject) => entry.file(resolveFile, reject))
  }

  async function readDroppedDirectoryEntries(entry: DroppedDirectoryEntry) {
    const reader = entry.createReader()
    const entries: DroppedEntry[] = []

    while (true) {
      const chunk = await new Promise<DroppedEntry[]>((resolveEntries, reject) =>
        reader.readEntries(resolveEntries, reject),
      )
      if (chunk.length === 0) {
        return entries
      }
      entries.push(...chunk)
    }
  }

  async function collectDroppedEntry(
    entry: DroppedEntry,
    parentPath: string,
    selections: UploadSelection[],
  ) {
    const relativePath = [parentPath, entry.name].filter(Boolean).join('/')
    if (entry.isFile) {
      const file = await readDroppedFile(entry)
      const directory = getUploadDirectory(relativePath)
      selections.push({
        file,
        name: relativePath,
        path: directory ? resolve(getCurrentPath(), directory) : getCurrentPath(),
        relativePath,
      })
      return
    }

    const entries = await readDroppedDirectoryEntries(entry)
    for (const childEntry of entries) {
      await collectDroppedEntry(childEntry, relativePath, selections)
    }
  }

  async function collectDroppedUploads(dataTransfer: DataTransfer) {
    const selections: UploadSelection[] = []
    const items = Array.from(dataTransfer.items)
    const supportsEntries = items.some((item) => 'webkitGetAsEntry' in item)

    if (supportsEntries) {
      for (const item of items) {
        const entry = (
          item as unknown as { webkitGetAsEntry?: () => DroppedEntry | null }
        ).webkitGetAsEntry?.()
        if (entry) {
          await collectDroppedEntry(entry, '', selections)
        }
      }
      return selections
    }

    return Array.from(dataTransfer.files).map((file) => ({
      file,
      name: file.name,
      path: getCurrentPath(),
      relativePath: file.name,
    }))
  }

  async function uploadSelections(selectedUploads: UploadSelection[], successMessage: string) {
    const connectionId = getConnectionId()
    if (!connectionId || selectedUploads.length === 0) {
      return
    }
    const batchId = uploadCenterStore.createBatch(connectionId, getCurrentPath(), selectedUploads)
    const controller = new AbortController()
    uploadCenterStore.clearBatchError(batchId)
    uploadCenterStore.registerBatchController(batchId, controller)

    let hasUploadedFiles = false

    try {
      await ensureUploadDirectories(
        connectionId,
        selectedUploads.map((item) => item.relativePath),
      )

      for (const [index, upload] of selectedUploads.entries()) {
        if (uploadCenterStore.isBatchCancelled(batchId)) {
          break
        }

        const batch = uploadCenterStore.batches.find((item) => item.id === batchId)
        const task = batch?.tasks[index]
        if (!task) {
          continue
        }

        uploadCenterStore.updateTask(task.id, {
          loaded: 0,
          progress: 0,
          status: 'uploading',
          total: upload.file.size,
        })

        const formData = new FormData()
        formData.append('file', upload.file, getUploadFilename(upload.relativePath, upload.file))
        await filesApi.upload(
          connectionId,
          upload.path,
          formData,
          (progressEvent) => {
            const total = progressEvent.total ?? upload.file.size
            const loaded = Math.min(progressEvent.loaded, total)

            uploadCenterStore.updateTask(task.id, {
              loaded,
              progress: total > 0 ? Math.min(100, Math.round((loaded / total) * 100)) : 0,
              total,
            })
          },
          controller.signal,
        )

        uploadCenterStore.updateTask(task.id, {
          loaded: upload.file.size,
          progress: 100,
          status: 'success',
          total: upload.file.size,
        })
        hasUploadedFiles = true
      }

      if (uploadCenterStore.isBatchCancelled(batchId)) {
        if (hasUploadedFiles) {
          await refreshFiles()
        }
        return
      }

      await refreshFiles()
      getUiApi().message.success(successMessage)
    } catch (error) {
      if (isTransferCancelled(error) || uploadCenterStore.isBatchCancelled(batchId)) {
        if (!uploadCenterStore.isBatchCancelled(batchId)) {
          uploadCenterStore.cancelBatch(batchId)
        }

        if (hasUploadedFiles) {
          await refreshFiles()
        }
        return
      }

      const batch = uploadCenterStore.batches.find((item) => item.id === batchId)
      const uploadingTask = batch?.tasks.find((task) => task.status === 'uploading')
      if (uploadingTask) {
        uploadCenterStore.updateTask(uploadingTask.id, {
          status: 'error',
        })
      }

      uploadCenterStore.markBatchError(
        batchId,
        error instanceof Error ? error.message : '上传失败。',
      )
      console.error('Failed to upload files', error)
      getUiApi().message.error('上传失败。')
    } finally {
      uploadCenterStore.clearBatchController(batchId)
    }
  }

  async function handleUploadChange(event: Event) {
    const input = event.target as HTMLInputElement
    const files = input.files
    if (!files || files.length === 0) {
      return
    }

    try {
      const selectedUploads = Array.from(files).map((file) => ({
        file,
        name: file.name,
        path: getCurrentPath(),
        relativePath: file.name,
      }))
      await uploadSelections(selectedUploads, `已上传 ${files.length} 个文件。`)
    } finally {
      input.value = ''
    }
  }

  async function handleDirectoryUploadChange(event: Event) {
    const input = event.target as HTMLInputElement
    const files = input.files
    if (!files || files.length === 0) {
      return
    }

    try {
      const selectedUploads = Array.from(files).map((file) => {
        const relativePath = getUploadRelativePath(file)
        const directory = getUploadDirectory(relativePath)
        return {
          file,
          name: relativePath,
          path: directory ? resolve(getCurrentPath(), directory) : getCurrentPath(),
          relativePath,
        }
      })
      await uploadSelections(selectedUploads, `已上传目录中的 ${files.length} 个文件。`)
    } finally {
      input.value = ''
    }
  }

  async function handleUploadDrop(event: DragEvent) {
    dragDepth.value = 0
    isDraggingUpload.value = false

    if (!isFileDrag(event) || !event.dataTransfer) {
      return
    }
    if (isUploading.value) {
      getUiApi().message.warning('请等待当前传输任务完成后再上传。')
      return
    }
    if (!getConnectionId()) {
      getUiApi().message.error('当前连接不可用，无法上传。')
      return
    }

    try {
      const selectedUploads = await collectDroppedUploads(event.dataTransfer)
      if (selectedUploads.length === 0) {
        getUiApi().message.warning('未找到可上传的文件，空目录不会被上传。')
        return
      }
      await uploadSelections(selectedUploads, `已拖放上传 ${selectedUploads.length} 个文件。`)
    } catch (error) {
      console.error('Failed to read dropped files', error)
      getUiApi().message.error('无法读取拖放的文件。')
    }
  }

  return {
    fileInputRef,
    directoryInputRef,
    isDraggingUpload,
    isUploading,
    triggerUpload,
    triggerDirectoryUpload,
    handleUploadChange,
    handleDirectoryUploadChange,
    handleUploadDragEnter,
    handleUploadDragLeave,
    handleUploadDrop,
  }
}
