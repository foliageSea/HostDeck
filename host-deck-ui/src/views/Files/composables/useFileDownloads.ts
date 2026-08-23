import { filesApi, type FileItem } from '@/api/files'
import { getUiApi } from '@/lib/ui'
import { useUploadCenterStore } from '@/stores/upload-center'
import { basename, resolve } from '@/utils/path'
import { getDownloadProgress, isTransferCancelled } from '../utils/transfer'

export interface UseFileDownloadsOptions {
  getConnectionId(): string | null
  getCurrentPath(): string
  getSelectedFiles(): FileItem[]
}

export function useFileDownloads({
  getConnectionId,
  getCurrentPath,
  getSelectedFiles,
}: UseFileDownloadsOptions) {
  const uploadCenterStore = useUploadCenterStore()

  async function downloadSelectedFiles() {
    const connectionId = getConnectionId()
    const selectedFiles = getSelectedFiles()
    if (!connectionId || selectedFiles.length === 0) {
      return
    }

    const filesToDownload = [...selectedFiles]
    const fileConnectionId = connectionId
    const batchPath = getCurrentPath()
    const downloadPaths = filesToDownload.map((file) => resolve(batchPath, file.filename))
    const batchId = uploadCenterStore.createBatch(
      fileConnectionId,
      batchPath,
      filesToDownload.map((file, index) => ({
        name: file.filename,
        path: downloadPaths[index] ?? batchPath,
        size: file.size,
      })),
      'files-download',
    )
    const controller = new AbortController()
    uploadCenterStore.clearBatchError(batchId)
    uploadCenterStore.registerBatchController(batchId, controller)

    try {
      let blob: Blob
      let filename: string

      if (filesToDownload.length === 1 && !filesToDownload[0]?.isDirectory) {
        const singleFile = filesToDownload[0]
        const task = uploadCenterStore.batches.find((item) => item.id === batchId)?.tasks.at(0)

        if (task) {
          uploadCenterStore.updateTask(task.id, {
            status: 'downloading',
            total: singleFile.size,
          })
        }

        blob = await filesApi.download(
          fileConnectionId,
          downloadPaths[0] ?? resolve(batchPath, singleFile.filename),
          (progressEvent) => {
            if (!task) {
              return
            }

            const total = progressEvent.total ?? singleFile.size
            const loaded = Math.min(progressEvent.loaded, total || progressEvent.loaded)
            uploadCenterStore.updateTask(task.id, {
              loaded,
              progress: getDownloadProgress(loaded, total),
              total,
            })
          },
          controller.signal,
        )
        filename = basename(singleFile.filename)

        if (task) {
          const total = singleFile.size || blob.size
          const loaded = Math.max(total, blob.size)
          uploadCenterStore.updateTask(task.id, {
            loaded,
            progress: 100,
            status: 'success',
            total: loaded,
          })
        }
      } else {
        const batch = uploadCenterStore.batches.find((item) => item.id === batchId)
        for (const task of batch?.tasks ?? []) {
          uploadCenterStore.updateTask(task.id, {
            status: 'downloading',
          })
        }

        const estimatedTotal = filesToDownload.reduce((sum, file) => sum + file.size, 0)
        blob = await filesApi.batchDownload(
          fileConnectionId,
          downloadPaths,
          (progressEvent) => {
            const loaded = progressEvent.loaded
            let remainingLoaded = loaded

            for (const task of batch?.tasks ?? []) {
              const taskLoaded = task.total > 0 ? Math.min(task.total, remainingLoaded) : 0
              remainingLoaded = Math.max(0, remainingLoaded - taskLoaded)
              uploadCenterStore.updateTask(task.id, {
                loaded: taskLoaded,
                progress: getDownloadProgress(taskLoaded, task.total),
              })
            }
          },
          controller.signal,
        )
        filename = 'download.tar.gz'

        let remainingLoaded = Math.max(estimatedTotal, blob.size)
        for (const task of batch?.tasks ?? []) {
          const taskLoaded = task.total > 0 ? Math.min(task.total, remainingLoaded) : task.total
          remainingLoaded = Math.max(0, remainingLoaded - taskLoaded)
          uploadCenterStore.updateTask(task.id, {
            loaded: taskLoaded,
            progress: 100,
            status: 'success',
            total: taskLoaded,
          })
        }
      }

      const url = window.URL.createObjectURL(blob)
      const anchor = document.createElement('a')
      anchor.href = url
      anchor.download = filename
      anchor.click()
      window.URL.revokeObjectURL(url)
    } catch (error) {
      if (isTransferCancelled(error) || uploadCenterStore.isBatchCancelled(batchId)) {
        if (!uploadCenterStore.isBatchCancelled(batchId)) {
          uploadCenterStore.cancelBatch(batchId)
        }
        return
      }

      const batch = uploadCenterStore.batches.find((item) => item.id === batchId)
      for (const task of batch?.tasks ?? []) {
        if (task.status === 'pending' || task.status === 'downloading') {
          uploadCenterStore.updateTask(task.id, {
            status: 'error',
          })
        }
      }
      uploadCenterStore.markBatchError(
        batchId,
        error instanceof Error ? error.message : '下载失败。',
      )
      console.error('Failed to download selection', error)
      getUiApi().message.error('下载失败。')
    } finally {
      uploadCenterStore.clearBatchController(batchId)
    }
  }

  return { downloadSelectedFiles }
}
