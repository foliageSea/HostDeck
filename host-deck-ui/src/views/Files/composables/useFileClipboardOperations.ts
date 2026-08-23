import { computed, watch } from 'vue'
import type { FileItem, FileTaskType } from '@/api/files'
import { getUiApi } from '@/lib/ui'
import { useFileClipboardStore, type FileClipboardOperation } from '@/stores/file-clipboard'
import { resolve } from '@/utils/path'

interface FileClipboardOperationsDependencies {
  getConnectionId: () => string | null
  getHost: () => string
  getPort: () => number | null
  getUsername: () => string
  getCurrentPath: () => string
  getFiles: () => FileItem[]
  getSelectedFiles: () => FileItem[]
  getWindowId: () => string | undefined
  setSelectedNames: (names: string[]) => void
  refreshFiles: () => Promise<unknown>
  startRemoteTask: (
    type: FileTaskType,
    items: Array<{ sourcePath: string; targetPath?: string }>,
  ) => Promise<unknown | null>
}

export function useFileClipboardOperations({
  getConnectionId,
  getHost,
  getPort,
  getUsername,
  getCurrentPath,
  getFiles,
  getSelectedFiles,
  getWindowId,
  setSelectedNames,
  refreshFiles,
  startRemoteTask,
}: FileClipboardOperationsDependencies) {
  const fileClipboardStore = useFileClipboardStore()
  const currentConnectionKey = computed(() => {
    const connectionId = getConnectionId()
    if (connectionId) return connectionId

    const host = getHost().trim()
    const username = getUsername().trim()
    const port = getPort()
    return host && username && port !== null ? `${username}@${host}:${port}` : ''
  })
  const clipboardPayload = computed(() => fileClipboardStore.payload)
  const canPasteToCurrentPath = computed(() => {
    const payload = clipboardPayload.value
    return Boolean(
      payload && payload.entries.length > 0 && payload.connectionKey === currentConnectionKey.value,
    )
  })
  const clipboardPasteLabel = computed(() => {
    if (!clipboardPayload.value) return '粘贴到此处'
    return clipboardPayload.value.operation === 'move' ? '粘贴移动到此处' : '粘贴复制到此处'
  })

  function isPathInsideDirectory(path: string, directoryPath: string) {
    return path === directoryPath || path.startsWith(`${directoryPath}/`)
  }

  function getClipboardValidationError(targetPath: string) {
    const payload = clipboardPayload.value
    if (!payload || payload.entries.length === 0) {
      return '没有可粘贴的项目。'
    }

    if (payload.connectionKey !== currentConnectionKey.value) {
      return '只能在当前连接的文件窗口之间复制或移动。'
    }

    if (payload.sourcePath === targetPath) {
      return '不能粘贴到原目录。'
    }

    const invalidDirectoryEntry = payload.entries.find(
      (entry) => entry.isDirectory && isPathInsideDirectory(targetPath, entry.path),
    )
    if (invalidDirectoryEntry) {
      return `不能将目录 ${invalidDirectoryEntry.filename} 粘贴到自身或子目录。`
    }

    const existingNames = new Set(getFiles().map((file) => file.filename))
    const conflictNames = payload.entries
      .map((entry) => entry.filename)
      .filter((filename) => existingNames.has(filename))

    if (conflictNames.length > 0) {
      return `当前目录已存在同名项目：${conflictNames.join('、')}`
    }

    return null
  }

  function saveClipboard(operation: FileClipboardOperation) {
    const selectedFiles = getSelectedFiles()
    if (selectedFiles.length === 0 || !currentConnectionKey.value) return

    fileClipboardStore.setPayload({
      connectionKey: currentConnectionKey.value,
      entries: selectedFiles.map((file) => ({
        filename: file.filename,
        isDirectory: file.isDirectory,
        path: resolve(getCurrentPath(), file.filename),
      })),
      operation,
      sourcePath: getCurrentPath(),
    })

    getUiApi().message.success(
      operation === 'move'
        ? `已标记移动 ${selectedFiles.length} 个项目，请在目标目录粘贴。`
        : `已复制 ${selectedFiles.length} 个项目，请在目标目录粘贴。`,
    )
  }

  async function pasteClipboardItems() {
    if (!getConnectionId()) return

    const targetPath = getCurrentPath()
    const validationError = getClipboardValidationError(targetPath)
    if (validationError) {
      getUiApi().message.error(validationError)
      return
    }

    const payload = clipboardPayload.value
    if (!payload) return

    const task = await startRemoteTask(
      payload.operation,
      payload.entries.map((entry) => ({
        sourcePath: entry.path,
        targetPath: resolve(targetPath, entry.filename),
      })),
    )
    if (!task) return
    setSelectedNames(payload.entries.map((entry) => entry.filename))
    if (payload.operation === 'move') fileClipboardStore.clearPayload()
  }

  watch(
    () => fileClipboardStore.refreshEvent,
    (event) => {
      if (!event || event.sourceWindowId === getWindowId() || event.path !== getCurrentPath()) {
        return
      }

      void refreshFiles()
    },
  )

  return { canPasteToCurrentPath, clipboardPasteLabel, pasteClipboardItems, saveClipboard }
}
