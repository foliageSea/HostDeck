import { onBeforeUnmount } from 'vue'
import { filesApi, type FileTask, type FileTaskType } from '@/api/files'
import { getUiApi } from '@/lib/ui'
import { useFileClipboardStore } from '@/stores/file-clipboard'
import { useUploadCenterStore } from '@/stores/upload-center'
import { isTransferCancelled } from '../utils/transfer'

interface RemoteFileTaskDependencies {
  getConnectionId: () => string | null
  getCurrentPath: () => string
  getWindowId: () => string | undefined
  refreshFiles: () => Promise<unknown>
}

export function useRemoteFileTasks({
  getConnectionId,
  getCurrentPath,
  getWindowId,
  refreshFiles,
}: RemoteFileTaskDependencies) {
  const fileClipboardStore = useFileClipboardStore()
  const uploadCenterStore = useUploadCenterStore()
  const controllers = new Map<string, AbortController>()

  function watchRemoteTask(task: FileTask) {
    if (controllers.has(task.id)) return

    const controller = new AbortController()
    controllers.set(task.id, controller)
    void filesApi
      .watchTask(
        task.id,
        (nextTask) => {
          uploadCenterStore.upsertRemoteTask(nextTask)
          if (
            nextTask.status === 'success' ||
            nextTask.status === 'failed' ||
            nextTask.status === 'cancelled'
          ) {
            controllers.delete(nextTask.id)
            void refreshFiles()
            fileClipboardStore.emitRefresh(getCurrentPath(), getWindowId())
          }
        },
        controller.signal,
      )
      .catch((error: unknown) => {
        if (!isTransferCancelled(error)) console.error('Failed to watch file task', error)
      })
  }

  async function startRemoteTask(
    type: FileTaskType,
    items: Array<{ sourcePath: string; targetPath?: string }>,
  ) {
    const connectionId = getConnectionId()
    if (!connectionId) return null

    try {
      const task = await filesApi.createTask(connectionId, type, items)
      uploadCenterStore.upsertRemoteTask(task)
      watchRemoteTask(task)
      getUiApi().message.success('已加入任务中心。')
      return task
    } catch (error) {
      console.error('Failed to create file task', error)
      getUiApi().message.error('创建文件任务失败。')
      return null
    }
  }

  async function restoreRemoteTasks() {
    const connectionId = getConnectionId()
    if (!connectionId) return

    try {
      const tasks = await filesApi.listTasks(connectionId)
      tasks.forEach((task) => {
        uploadCenterStore.upsertRemoteTask(task)
        if (task.status === 'queued' || task.status === 'running') watchRemoteTask(task)
      })
    } catch (error) {
      console.error('Failed to restore file tasks', error)
    }
  }

  onBeforeUnmount(() => {
    for (const controller of controllers.values()) controller.abort()
    controllers.clear()
  })

  return { restoreRemoteTasks, startRemoteTask }
}
