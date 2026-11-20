import { onBeforeUnmount } from 'vue'
import { filesApi, type FileTaskType } from '@/api/files'
import { getUiApi } from '@/lib/ui'
import { useUploadCenterStore } from '@/stores/upload-center'
import { dirname } from '@/utils/path'

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
  const uploadCenterStore = useUploadCenterStore()

  // Refresh the initiating window and sibling windows viewing affected paths, even if the
  // initiator has closed. Unmount only detaches the UI callback, not the remote task stream.
  const stopRefresh = uploadCenterStore.onRemoteTaskCompleted((task, sourceWindowId) => {
    const localTask = sourceWindowId !== undefined && sourceWindowId === getWindowId()
    if (task.connectionId !== getConnectionId()) return
    const path = getCurrentPath()
    if (
      localTask ||
      task.items.some(
        (item) =>
          dirname(item.sourcePath) === path ||
          (item.targetPath && dirname(item.targetPath) === path),
      )
    ) {
      void refreshFiles().catch((error) => console.error('Failed to refresh files', error))
    }
  })
  onBeforeUnmount(stopRefresh)

  async function startRemoteTask(
    type: FileTaskType,
    items: Array<{ sourcePath: string; targetPath?: string }>,
  ) {
    const connectionId = getConnectionId()
    if (!connectionId) return null

    try {
      const task = await filesApi.createTask(connectionId, type, items)
      uploadCenterStore.upsertRemoteTask(task, { snapshot: true, windowId: getWindowId() })
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
      await uploadCenterStore.restoreRemoteTasks(connectionId)
    } catch (error) {
      console.error('Failed to restore file tasks', error)
    }
  }

  return { restoreRemoteTasks, startRemoteTask }
}
