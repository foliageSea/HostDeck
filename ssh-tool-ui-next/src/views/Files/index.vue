<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useLocalStorage } from '@vueuse/core'
import {
  ArrowLeft,
  ArrowRight,
  Help,
  ArrowUp,
  Close,
  Download,
  FolderAdd,
  Grid,
  List,
  LocationStar,
  Pin,
  PinFilled,
  Renew,
  Star,
  StarFilled,
  Terminal,
  Upload,
} from '@vicons/carbon'
import { filesApi, type FileItem } from '@/api/files'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { useFileClipboardStore } from '@/stores/file-clipboard'
import { createFileStore } from '@/stores/file'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'
import { useUploadCenterStore } from '@/stores/upload-center'
import { basename, resolve } from '@/utils/path'
import FileBrowserContent from './components/FileBrowserContent.vue'
import FileFavoriteSidebar from './components/FileFavoriteSidebar.vue'
import FileNameDialog from './components/FileNameDialog.vue'

const props = defineProps<{
  windowId?: string
  connectionId?: string
  host?: string
  path?: string
  port?: number
  username?: string
}>()

const desktopStore = useDesktopStore()
const fileClipboardStore = useFileClipboardStore()
const settingsStore = useSettingsStore()
const sshStore = useSshStore()
const uploadCenterStore = useUploadCenterStore()

const fileStore = createFileStore({
  get connectionId() {
    return (props.connectionId as string | undefined) ?? sshStore.connectionId
  },
  get host() {
    return (props.host as string | undefined) ?? sshStore.host
  },
  get port() {
    return (props.port as number | undefined) ?? sshStore.port
  },
  get username() {
    return (props.username as string | undefined) ?? sshStore.username
  },
})

const currentPathInput = ref('/')
const createDialogMode = ref<'directory' | 'file'>('directory')
const newItemName = ref('')
const renameValue = ref('')
const editingPath = ref(false)
const showCreateDialog = ref(false)
const showRenameDialog = ref(false)
const showDeleteDialog = ref(false)
const deletingFiles = ref(false)
const fileInputRef = ref<HTMLInputElement | null>(null)
const contextMenu = ref<{ type: 'file' | 'blank'; x: number; y: number } | null>(null)
const isFavoriteSidebarVisible = useLocalStorage('ssh-tool:files:favorite-sidebar-visible', true)

const selectedFile = computed(() => fileStore.selectedFile)
const selectedFiles = computed(() =>
  fileStore.files.filter((file) => fileStore.selectedNames.includes(file.filename)),
)
const currentConnectionKey = computed(() => {
  const connectionId = (props.connectionId as string | undefined) ?? sshStore.connectionId
  if (connectionId) {
    return connectionId
  }

  const host = ((props.host as string | undefined) ?? sshStore.host).trim()
  const username = ((props.username as string | undefined) ?? sshStore.username).trim()
  const port = (props.port as number | undefined) ?? sshStore.port
  return host && username && port !== null ? `${username}@${host}:${port}` : ''
})
const clipboardPayload = computed(() => fileClipboardStore.payload)
const canPasteToCurrentPath = computed(() => {
  const payload = clipboardPayload.value
  return Boolean(payload && payload.entries.length > 0 && payload.connectionKey === currentConnectionKey.value)
})
const clipboardPasteLabel = computed(() => {
  if (!clipboardPayload.value) {
    return '粘贴到此处'
  }

  return clipboardPayload.value.operation === 'move' ? '粘贴移动到此处' : '粘贴复制到此处'
})
const isUploading = computed(() => uploadCenterStore.activeTaskCount > 0)
const isCurrentPathFavorite = computed(() => fileStore.isFavoritePath(fileStore.currentPath))
const isCurrentPathPinned = computed(() => desktopStore.isDirectoryPinned(fileStore.currentPath))
const selectedDirectoryPath = computed(() => {
  if (selectedFiles.value.length !== 1 || !selectedFile.value?.isDirectory) {
    return null
  }

  return resolve(fileStore.currentPath, selectedFile.value.filename)
})
const isSelectedDirectoryPinned = computed(() =>
  selectedDirectoryPath.value ? desktopStore.isDirectoryPinned(selectedDirectoryPath.value) : false,
)
const canOpenSelectedFileInEditor = computed(() => {
  const file = selectedFile.value
  return selectedFiles.value.length === 1 && file !== null && !file.isDirectory
})
const contextMenuOptions = computed(() => {
  if (contextMenu.value?.type === 'file') {
    const options = [
      { label: '打开', key: 'open', disabled: selectedFiles.value.length !== 1 },
      { label: '使用文本编辑器打开', key: 'open-in-editor', disabled: !canOpenSelectedFileInEditor.value },
      { label: '下载', key: 'download', disabled: selectedFiles.value.length === 0 },
      { label: '复制', key: 'copy', disabled: selectedFiles.value.length === 0 },
      { label: '移动', key: 'move', disabled: selectedFiles.value.length === 0 },
      { type: 'divider', key: 'file-divider-1' },
      { label: '重命名', key: 'rename', disabled: selectedFiles.value.length !== 1 },
      { label: '删除', key: 'delete', disabled: selectedFiles.value.length === 0 },
    ]

    if (selectedDirectoryPath.value) {
      options.splice(2, 0, {
        label: fileStore.isFavoritePath(selectedDirectoryPath.value) ? '取消收藏该目录' : '收藏该目录',
        key: 'toggle-selected-directory-favorite',
        disabled: false,
      })
      options.splice(3, 0, {
        label: isSelectedDirectoryPinned.value ? '从桌面移除该目录' : '将该目录钉到桌面',
        key: 'toggle-selected-directory-pin',
        disabled: false,
      })
    }

    return options
  }

  return [
    { label: '新建目录', key: 'new-directory' },
    { label: '新建文件', key: 'new-file' },
    { label: '上传', key: 'upload', disabled: isUploading.value },
    { label: clipboardPasteLabel.value, key: 'paste', disabled: !canPasteToCurrentPath.value },
    { type: 'divider', key: 'blank-divider-1' },
    { label: '刷新', key: 'refresh' },
    { label: '全选', key: 'select-all', disabled: fileStore.displayFiles.length === 0 },
    { type: 'divider', key: 'blank-divider-2' },
    { label: isCurrentPathFavorite.value ? '取消收藏当前目录' : '收藏当前目录', key: 'toggle-current-favorite' },
    { label: isCurrentPathPinned.value ? '从桌面移除当前目录' : '将当前目录钉到桌面', key: 'toggle-current-directory-pin' },
    { label: '在当前目录打开终端', key: 'terminal' },
  ]
})
const breadcrumbs = computed(() => {
  const path = fileStore.currentPath
  if (path === '/') {
    return [{ label: '根目录', path: '/' }]
  }

  const segments = path.split('/').filter(Boolean)
  return [
    { label: '根目录', path: '/' },
    ...segments.map((segment, index) => ({
      label: segment,
      path: `/${segments.slice(0, index + 1).join('/')}`,
    })),
  ]
})

const editableExtensions = new Set([
  'txt',
  'md',
  'json',
  'yaml',
  'yml',
  'xml',
  'js',
  'ts',
  'tsx',
  'jsx',
  'vue',
  'css',
  'scss',
  'less',
  'html',
  'sh',
  'bash',
  'zsh',
  'py',
  'go',
  'rs',
  'java',
  'c',
  'cpp',
  'h',
  'hpp',
  'sql',
  'ini',
  'conf',
  'env',
  'log',
])

const imageExtensions = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'ico'])
const videoExtensions = new Set(['mp4', 'webm', 'ogg', 'mov', 'mkv', 'avi'])

function syncPathInput() {
  currentPathInput.value = fileStore.currentPath
}

function startPathEditing() {
  syncPathInput()
  editingPath.value = true
}

function stopPathEditing() {
  editingPath.value = false
  syncPathInput()
}

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

function formatModifyTime(value?: string) {
  if (!value) {
    return '-'
  }

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) {
    return value
  }

  return date.toLocaleString('zh-CN')
}

function formatFavoritePath(path: string) {
  return basename(path) || '根目录'
}

function handleFileClick(file: FileItem, event: MouseEvent) {
  closeContextMenu()
  fileStore.selectFile(file, {
    append: event.ctrlKey || event.metaKey,
    range: event.shiftKey,
  })
}

function handleSelectNames(names: string[]) {
  closeContextMenu()
  fileStore.setSelectedNames(names)
}

function openFileContextMenu(file: FileItem, event: MouseEvent) {
  if (!fileStore.selectedNames.includes(file.filename)) {
    fileStore.selectFile(file)
  }

  contextMenu.value = {
    type: 'file',
    x: event.clientX,
    y: event.clientY,
  }
}

function openBlankContextMenu(event: MouseEvent) {
  fileStore.clearSelection()
  contextMenu.value = {
    type: 'blank',
    x: event.clientX,
    y: event.clientY,
  }
}

function closeContextMenu() {
  contextMenu.value = null
}

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

  const existingNames = new Set(fileStore.files.map((file) => file.filename))
  const conflictNames = payload.entries
    .map((entry) => entry.filename)
    .filter((filename) => existingNames.has(filename))

  if (conflictNames.length > 0) {
    return `当前目录已存在同名项目：${conflictNames.join('、')}`
  }

  return null
}

function saveClipboard(operation: 'copy' | 'move') {
  if (selectedFiles.value.length === 0 || !currentConnectionKey.value) {
    return
  }

  fileClipboardStore.setPayload({
    connectionKey: currentConnectionKey.value,
    entries: selectedFiles.value.map((file) => ({
      filename: file.filename,
      isDirectory: file.isDirectory,
      path: resolve(fileStore.currentPath, file.filename),
    })),
    operation,
    sourcePath: fileStore.currentPath,
  })

  getUiApi().message.success(
    operation === 'move'
      ? `已标记移动 ${selectedFiles.value.length} 个项目，请在目标目录粘贴。`
      : `已复制 ${selectedFiles.value.length} 个项目，请在目标目录粘贴。`,
  )
}

async function pasteClipboardItems() {
  if (!fileStore.sessionId) {
    return
  }

  const targetPath = fileStore.currentPath
  const validationError = getClipboardValidationError(targetPath)
  if (validationError) {
    getUiApi().message.error(validationError)
    return
  }

  const payload = clipboardPayload.value
  if (!payload) {
    return
  }

  try {
    await Promise.all(
      payload.entries.map((entry) => {
        const nextPath = resolve(targetPath, entry.filename)
        return payload.operation === 'move'
          ? filesApi.rename(fileStore.sessionId as string, entry.path, nextPath)
          : filesApi.copy(fileStore.sessionId as string, entry.path, nextPath)
      }),
    )

    await fileStore.fetchFiles()
    fileStore.setSelectedNames(payload.entries.map((entry) => entry.filename))
    fileClipboardStore.emitRefresh(targetPath, props.windowId)

    if (payload.operation === 'move') {
      fileClipboardStore.emitRefresh(payload.sourcePath, props.windowId)
      fileClipboardStore.clearPayload()
    }

    getUiApi().message.success(payload.operation === 'move' ? '移动成功。' : '复制成功。')
  } catch (error) {
    console.error('Failed to paste files', error)
    getUiApi().message.error(payload.operation === 'move' ? '移动失败。' : '复制失败。')
  }
}

function handleContextMenuSelect(key: string | number) {
  closeContextMenu()

  if (key === 'open' && selectedFile.value) {
    void openFile(selectedFile.value)
    return
  }

  if (key === 'open-in-editor' && selectedFile.value) {
    openFileInEditor(selectedFile.value)
    return
  }

  if (key === 'download') {
    void downloadSelectedFiles()
    return
  }

  if (key === 'copy') {
    saveClipboard('copy')
    return
  }

  if (key === 'move') {
    saveClipboard('move')
    return
  }

  if (key === 'rename') {
    openRenameDialog()
    return
  }

  if (key === 'delete') {
    showDeleteDialog.value = true
    return
  }

  if (key === 'new-directory') {
    openCreate('directory')
    return
  }

  if (key === 'new-file') {
    openCreate('file')
    return
  }

  if (key === 'upload') {
    triggerUpload()
    return
  }

  if (key === 'paste') {
    void pasteClipboardItems()
    return
  }

  if (key === 'refresh') {
    void fileStore.fetchFiles()
    return
  }

  if (key === 'select-all') {
    fileStore.selectAll()
    return
  }

  if (key === 'toggle-current-favorite') {
    toggleCurrentFavorite()
    return
  }

  if (key === 'toggle-selected-directory-favorite') {
    toggleSelectedDirectoryFavorite()
    return
  }

  if (key === 'toggle-current-directory-pin') {
    toggleCurrentDesktopPin()
    return
  }

  if (key === 'toggle-selected-directory-pin') {
    toggleSelectedDirectoryDesktopPin()
    return
  }

  if (key === 'terminal') {
    openTerminalHere()
  }
}

function openFileInEditor(file: FileItem) {
  if (file.isDirectory || !fileStore.sessionId) {
    return
  }

  desktopStore.openWindow('editor', {
    path: resolve(fileStore.currentPath, file.filename),
    sessionId: fileStore.sessionId,
    title: file.filename,
  })
}

async function openFile(file: FileItem) {
  closeContextMenu()
  fileStore.selectFile(file)
  if (!file.isDirectory) {
    const extension = file.filename.split('.').pop()?.toLowerCase() || ''

    if (editableExtensions.has(extension)) {
      openFileInEditor(file)
      return
    }

    if (imageExtensions.has(extension) || videoExtensions.has(extension)) {
      const playlist = fileStore.files
        .filter((item) => !item.isDirectory)
        .filter((item) => {
          const itemExtension = item.filename.split('.').pop()?.toLowerCase() || ''
          return imageExtensions.has(itemExtension) || videoExtensions.has(itemExtension)
        })
        .map((item) => {
          const itemExtension = item.filename.split('.').pop()?.toLowerCase() || ''
          return {
            filename: item.filename,
            path: resolve(fileStore.currentPath, item.filename),
            type: videoExtensions.has(itemExtension) ? 'video' : 'image',
          }
        })

      desktopStore.openWindow('media-viewer', {
        path: resolve(fileStore.currentPath, file.filename),
        playlist,
        sessionId: fileStore.sessionId,
        title: file.filename,
      })
    }

    return
  }

  await fileStore.navigateTo(file.filename)
  syncPathInput()
}

async function submitPath() {
  await fileStore.navigateTo(currentPathInput.value)
  syncPathInput()
  editingPath.value = false
}

async function navigateToPath(path: string) {
  await fileStore.navigateTo(path)
  syncPathInput()
  editingPath.value = false
}

function toggleCurrentFavorite() {
  const added = fileStore.toggleFavoritePath(fileStore.currentPath)
  getUiApi().message.success(added ? '已收藏当前目录。' : '已取消收藏当前目录。')
}

function toggleSelectedDirectoryFavorite() {
  if (!selectedDirectoryPath.value) {
    return
  }

  const added = fileStore.toggleFavoritePath(selectedDirectoryPath.value)
  getUiApi().message.success(added ? '已收藏目录。' : '已取消收藏目录。')
}

function toggleCurrentDesktopPin() {
  const pinned = desktopStore.toggleDirectoryPin(fileStore.currentPath)
  getUiApi().message.success(pinned ? '已将当前目录钉到桌面。' : '已从桌面移除当前目录。')
}

function toggleSelectedDirectoryDesktopPin() {
  if (!selectedDirectoryPath.value) {
    return
  }

  const pinned = desktopStore.toggleDirectoryPin(selectedDirectoryPath.value)
  getUiApi().message.success(pinned ? '已将目录钉到桌面。' : '已从桌面移除该目录。')
}

function removeFavoritePath(path: string) {
  fileStore.removeFavoritePath(path)
  getUiApi().message.success('已移除收藏。')
}

function toggleFavoriteSidebar() {
  isFavoriteSidebarVisible.value = !isFavoriteSidebarVisible.value
}

async function navigateBack() {
  await fileStore.navigateBack()
  syncPathInput()
}

async function navigateForward() {
  await fileStore.navigateForward()
  syncPathInput()
}

async function navigateUp() {
  await fileStore.navigateUp()
  syncPathInput()
}

function openCreate(mode: 'directory' | 'file') {
  createDialogMode.value = mode
  newItemName.value = ''
  showCreateDialog.value = true
}

async function confirmCreate() {
  if (!fileStore.sessionId || !newItemName.value.trim()) {
    return
  }

  const nextPath = resolve(fileStore.currentPath, newItemName.value.trim())

  try {
    if (createDialogMode.value === 'directory') {
      await filesApi.mkdir(fileStore.sessionId, nextPath)
    } else {
      await filesApi.writeFile(fileStore.sessionId, nextPath, '')
    }

    showCreateDialog.value = false
    await fileStore.fetchFiles()
    getUiApi().message.success(createDialogMode.value === 'directory' ? '目录已创建。' : '文件已创建。')
  } catch (error) {
    console.error('Failed to create file item', error)
    getUiApi().message.error('创建失败。')
  }
}

function openRenameDialog() {
  if (selectedFiles.value.length !== 1 || !selectedFile.value) {
    return
  }

  renameValue.value = selectedFile.value.filename
  showRenameDialog.value = true
}

async function confirmRename() {
  if (!fileStore.sessionId || !selectedFile.value || !renameValue.value.trim()) {
    return
  }

  try {
    await filesApi.rename(
      fileStore.sessionId,
      resolve(fileStore.currentPath, selectedFile.value.filename),
      resolve(fileStore.currentPath, renameValue.value.trim()),
    )
    showRenameDialog.value = false
    await fileStore.fetchFiles()
    getUiApi().message.success('重命名成功。')
  } catch (error) {
    console.error('Failed to rename file', error)
    getUiApi().message.error('重命名失败。')
  }
}

async function confirmDelete() {
  if (!fileStore.sessionId || selectedFiles.value.length === 0 || deletingFiles.value) {
    return
  }

  deletingFiles.value = true
  try {
    await Promise.all(
      selectedFiles.value.map((file) =>
        filesApi.delete(fileStore.sessionId as string, resolve(fileStore.currentPath, file.filename)),
      ),
    )

    showDeleteDialog.value = false
    fileStore.clearSelection()
    await fileStore.fetchFiles()
    getUiApi().message.success('删除成功。')
  } catch (error) {
    console.error('Failed to delete files', error)
    getUiApi().message.error('删除失败。')
  } finally {
    deletingFiles.value = false
  }
}

async function downloadSelectedFiles() {
  if (!fileStore.sessionId || selectedFiles.value.length === 0) {
    return
  }

  try {
    const fileSessionId = fileStore.sessionId
    let blob: Blob
    let filename: string

    if (selectedFiles.value.length === 1 && !selectedFiles.value[0]?.isDirectory) {
      const singleFile = selectedFiles.value[0]
      blob = await filesApi.download(fileSessionId, resolve(fileStore.currentPath, singleFile.filename))
      filename = basename(singleFile.filename)
    } else {
      blob = await filesApi.batchDownload(
        fileSessionId,
        selectedFiles.value.map((file) => resolve(fileStore.currentPath, file.filename)),
      )
      filename = 'download.tar.gz'
    }

    const url = window.URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = filename
    anchor.click()
    window.URL.revokeObjectURL(url)
  } catch (error) {
    console.error('Failed to download selection', error)
    getUiApi().message.error('下载失败。')
  }
}

function triggerUpload() {
  if (isUploading.value) {
    return
  }

  fileInputRef.value?.click()
}

function isUploadCancelled(error: unknown) {
  return typeof error === 'object' && error !== null && 'code' in error && error.code === 'ERR_CANCELED'
}

async function handleUploadChange(event: Event) {
  if (!fileStore.sessionId) {
    return
  }

  const input = event.target as HTMLInputElement
  const files = input.files
  if (!files || files.length === 0) {
    return
  }

  const selectedUploads = Array.from(files)
  const batchId = uploadCenterStore.createBatch(fileStore.sessionId, fileStore.currentPath, selectedUploads)
  const controller = new AbortController()
  uploadCenterStore.clearBatchError(batchId)
  uploadCenterStore.registerBatchController(batchId, controller)

  let hasUploadedFiles = false

  try {
    for (const [index, file] of selectedUploads.entries()) {
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
        total: file.size,
      })

      const formData = new FormData()
      formData.append('file', file, file.name)
      await filesApi.upload(fileStore.sessionId, fileStore.currentPath, formData, (progressEvent) => {
        const total = progressEvent.total ?? file.size
        const loaded = Math.min(progressEvent.loaded, total)

        uploadCenterStore.updateTask(task.id, {
          loaded,
          progress: total > 0 ? Math.min(100, Math.round((loaded / total) * 100)) : 0,
          total,
        })
      }, controller.signal)

      uploadCenterStore.updateTask(task.id, {
        loaded: file.size,
        progress: 100,
        status: 'success',
        total: file.size,
      })
      hasUploadedFiles = true
    }

    if (uploadCenterStore.isBatchCancelled(batchId)) {
      if (hasUploadedFiles) {
        await fileStore.fetchFiles()
      }
      return
    }

    await fileStore.fetchFiles()
    getUiApi().message.success(`已上传 ${files.length} 个文件。`)
  } catch (error) {
    if (isUploadCancelled(error) || uploadCenterStore.isBatchCancelled(batchId)) {
      if (!uploadCenterStore.isBatchCancelled(batchId)) {
        uploadCenterStore.cancelBatch(batchId)
      }

      if (hasUploadedFiles) {
        await fileStore.fetchFiles()
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

    uploadCenterStore.markBatchError(batchId, error instanceof Error ? error.message : '上传失败。')
    console.error('Failed to upload files', error)
    getUiApi().message.error('上传失败。')
  } finally {
    uploadCenterStore.clearBatchController(batchId)
    input.value = ''
  }
}

function openTerminalHere() {
  const currentConnectionId = props.connectionId ?? sshStore.connectionId
  desktopStore.openWindow('terminal', {
    connectionId: currentConnectionId ?? undefined,
    cwd: fileStore.currentPath,
    host: props.host ?? sshStore.host,
    title: `终端 · ${fileStore.currentPath}`,
    username: props.username ?? sshStore.username,
  })
}

function handleKeydown(event: KeyboardEvent) {
  const target = event.target as HTMLElement | null
  if (target) {
    const tagName = target.tagName.toLowerCase()
    if (tagName === 'input' || tagName === 'textarea' || target.isContentEditable) {
      return
    }
  }

  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'a') {
    event.preventDefault()
    closeContextMenu()
    fileStore.selectAll()
    return
  }

  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'u') {
    event.preventDefault()
    triggerUpload()
    return
  }

  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'd') {
    event.preventDefault()
    void downloadSelectedFiles()
    return
  }

  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'c' && fileStore.hasSelection) {
    event.preventDefault()
    closeContextMenu()
    saveClipboard('copy')
    return
  }

  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'x' && fileStore.hasSelection) {
    event.preventDefault()
    closeContextMenu()
    saveClipboard('move')
    return
  }

  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'v') {
    event.preventDefault()
    closeContextMenu()
    void pasteClipboardItems()
    return
  }

  if (event.key === 'Delete' && fileStore.hasSelection) {
    event.preventDefault()
    closeContextMenu()
    showDeleteDialog.value = true
    return
  }

  if (event.key === 'F2' && selectedFiles.value.length === 1) {
    event.preventDefault()
    closeContextMenu()
    openRenameDialog()
    return
  }

  if (event.key === 'Enter' && selectedFiles.value.length === 1 && selectedFile.value) {
    event.preventDefault()
    void openFile(selectedFile.value)
  }
}

onMounted(async () => {
  await fileStore.fetchFiles(props.path || '/')
  syncPathInput()
})

onBeforeUnmount(() => {
  void fileStore.disposeSession()
})

watch(
  () => fileClipboardStore.refreshEvent,
  (event) => {
    if (!event || event.sourceWindowId === props.windowId || event.path !== fileStore.currentPath) {
      return
    }

    void fileStore.fetchFiles()
  },
)
</script>

<template>
  <div class="flex h-full flex-col gap-[14px] p-[16px] outline-none"
    :class="settingsStore.isDark ? 'bg-[linear-gradient(180deg,rgba(15,23,42,0.14),rgba(15,23,42,0.04))]' : 'bg-[linear-gradient(180deg,rgba(255,255,255,0.68),rgba(226,232,240,0.34))]'"
    tabindex="0" @keydown="handleKeydown" @click.self="fileStore.clearSelection()">
    <input ref="fileInputRef" type="file" multiple hidden @change="handleUploadChange" />

    <div class="flex flex-wrap items-center justify-between gap-[12px]">
      <NSpace align="center" wrap>
        <NTooltip>
          <template #trigger>
            <NButton quaternary circle :disabled="fileStore.backHistory.length === 0" @click="navigateBack">
              <template #icon>
                <NIcon>
                  <ArrowLeft />
                </NIcon>
              </template>
            </NButton>
          </template>
          返回
        </NTooltip>
        <NTooltip>
          <template #trigger>
            <NButton quaternary circle :disabled="fileStore.forwardHistory.length === 0" @click="navigateForward">
              <template #icon>
                <NIcon>
                  <ArrowRight />
                </NIcon>
              </template>
            </NButton>
          </template>
          前进
        </NTooltip>
        <NTooltip>
          <template #trigger>
            <NButton quaternary circle @click="navigateUp">
              <template #icon>
                <NIcon>
                  <ArrowUp />
                </NIcon>
              </template>
            </NButton>
          </template>
          上级目录
        </NTooltip>
        <NTooltip>
          <template #trigger>
            <NButton quaternary circle @click="fileStore.fetchFiles()">
              <template #icon>
                <NIcon>
                  <Renew />
                </NIcon>
              </template>
            </NButton>
          </template>
          刷新
        </NTooltip>
      </NSpace>

      <div class="flex items-center gap-[8px] ">
        <NInput v-model:value="fileStore.search" placeholder="搜索当前目录" clearable class="w-[min(240px,60vw)]" />
        <div class="flex items-center gap-[8px] ">
          <NPopover trigger="hover" placement="bottom-end">
            <template #trigger>
              <NButton quaternary circle>
                <template #icon>
                  <NIcon>
                    <Help />
                  </NIcon>
                </template>
              </NButton>
            </template>
            <div class="flex flex-col gap-[6px] text-[12px]"
              :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.96)]' : 'text-[rgba(51,65,85,0.96)]'">
              <div>Ctrl/Cmd + Click：多选</div>
              <div>Shift + Click：范围选择</div>
              <div>Ctrl/Cmd + A：全选</div>
              <div>Ctrl/Cmd + C：复制</div>
              <div>Ctrl/Cmd + X：移动</div>
              <div>Ctrl/Cmd + V：粘贴</div>
              <div>Ctrl/Cmd + U：上传</div>
              <div>Ctrl/Cmd + D：下载</div>
              <div>Delete：删除</div>
              <div>F2：重命名</div>
              <div>Enter：打开选中项</div>
            </div>
          </NPopover>
          <NTooltip>
            <template #trigger>
              <NButton quaternary circle :type="fileStore.viewMode === 'list' ? 'primary' : 'default'"
                @click="fileStore.viewMode = 'list'">
                <template #icon>
                  <NIcon>
                    <List />
                  </NIcon>
                </template>
              </NButton>
            </template>
            列表视图
          </NTooltip>
          <NTooltip>
            <template #trigger>
              <NButton quaternary circle :type="fileStore.viewMode === 'grid' ? 'primary' : 'default'"
                @click="fileStore.viewMode = 'grid'">
                <template #icon>
                  <NIcon>
                    <Grid />
                  </NIcon>
                </template>
              </NButton>
            </template>
            网格视图
          </NTooltip>
        </div>
      </div>
    </div>

    <div class="flex min-h-0 flex-1 gap-[14px]">
      <FileFavoriteSidebar :current-path="fileStore.currentPath" :favorite-paths="fileStore.favoritePaths"
        :is-current-path-favorite="isCurrentPathFavorite" :visible="isFavoriteSidebarVisible"
        @navigate="navigateToPath" @remove="removeFavoritePath" @toggle-current-favorite="toggleCurrentFavorite"
        @toggle-visibility="toggleFavoriteSidebar" />

      <div class="flex min-h-0 min-w-0 flex-1 flex-col gap-[14px]">
        <div class="flex flex-wrap items-center justify-between gap-[12px]">
          <div v-if="!editingPath" class="min-w-[240px] flex-1 overflow-x-auto pb-[2px] app-scrollbar app-scrollbar-compact"
            :class="settingsStore.isDark ? 'app-scrollbar-dark' : 'app-scrollbar-light'">
            <NBreadcrumb>
              <NBreadcrumbItem v-for="item in breadcrumbs" :key="item.path">
                <button type="button" class="btn-reset hover:text-[rgba(96,165,250,0.95)]"
                  @click="navigateToPath(item.path)">
                  {{ item.label }}
                </button>
              </NBreadcrumbItem>
            </NBreadcrumb>
          </div>
          <div v-else class="path-editor min-w-[240px] flex-1">
            <NInput v-model:value="currentPathInput" placeholder="输入远程路径快速跳转" @keyup.enter="submitPath"
              @keyup.esc="stopPathEditing" @blur="stopPathEditing" />
          </div>

          <div class="flex flex-wrap items-center justify-end gap-[12px]">
            <NButton v-if="editingPath" type="primary" @mousedown.prevent @click="submitPath">跳转</NButton>
            <NTooltip v-else>
              <template #trigger>
                <NButton circle @click="startPathEditing">
                  <template #icon>
                    <NIcon>
                      <ArrowRight />
                    </NIcon>
                  </template>
                </NButton>
              </template>
              输入路径跳转
            </NTooltip>
            <NTooltip>
              <template #trigger>
                <NButton circle :type="isCurrentPathFavorite ? 'warning' : 'default'" @click="toggleCurrentFavorite">
                  <template #icon>
                    <NIcon>
                      <component :is="isCurrentPathFavorite ? StarFilled : Star" />
                    </NIcon>
                  </template>
                </NButton>
              </template>
              {{ isCurrentPathFavorite ? '取消收藏当前目录' : '收藏当前目录' }}
            </NTooltip>
            <NTooltip>
              <template #trigger>
                <NButton circle :type="isCurrentPathPinned ? 'primary' : 'default'" @click="toggleCurrentDesktopPin">
                  <template #icon>
                    <NIcon>
                      <component :is="isCurrentPathPinned ? PinFilled : Pin" />
                    </NIcon>
                  </template>
                </NButton>
              </template>
              {{ isCurrentPathPinned ? '从桌面移除当前目录' : '将当前目录钉到桌面' }}
            </NTooltip>
            <NPopover v-if="fileStore.favoritePaths.length > 0" trigger="click" placement="bottom-end">
              <template #trigger>
                <NButton circle class="md:hidden">
                  <template #icon>
                    <NIcon>
                      <LocationStar />
                    </NIcon>
                  </template>
                </NButton>
              </template>
              <div class="w-[min(360px,72vw)]">
                <div class="mb-[10px] text-[13px] font-600"
                  :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.96)]' : 'text-[rgba(51,65,85,0.96)]'">收藏目录</div>
                <NScrollbar style="max-height: 260px">
                  <div class="flex flex-col gap-[6px]">
                    <div v-for="path in fileStore.favoritePaths" :key="path"
                      class="flex min-w-0 items-center gap-[8px] rounded-[10px] py-[6px] pl-[10px] pr-[6px]"
                      :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.5)]' : 'bg-[rgba(241,245,249,0.92)]'">
                      <button type="button"
                        class="btn-reset truncate-line flex-1 text-left hover:text-[rgba(96,165,250,0.95)]" :title="path"
                        @click="navigateToPath(path)">
                        {{ formatFavoritePath(path) }}
                      </button>
                      <NButton quaternary circle size="tiny" @click.stop="removeFavoritePath(path)">
                        <template #icon>
                          <NIcon>
                            <Close />
                          </NIcon>
                        </template>
                      </NButton>
                    </div>
                  </div>
                </NScrollbar>
              </div>
            </NPopover>
            <NTooltip>
              <template #trigger>
                <NButton circle @click="openTerminalHere">
                  <template #icon>
                    <NIcon>
                      <Terminal />
                    </NIcon>
                  </template>
                </NButton>
              </template>
              在当前目录打开终端
            </NTooltip>
          </div>
        </div>

        <div class="flex w-full flex-wrap items-center justify-end gap-[12px]">
          <NButton @click="openCreate('directory')">
            <template #icon>
              <NIcon>
                <FolderAdd />
              </NIcon>
            </template>
            新建目录
          </NButton>
          <NButton @click="openCreate('file')">新建文件</NButton>
          <NButton :disabled="isUploading" :loading="isUploading" @click="triggerUpload">
            <template #icon>
              <NIcon>
                <Upload />
              </NIcon>
            </template>
            上传
          </NButton>
          <NButton :disabled="selectedFiles.length !== 1" @click="openRenameDialog">重命名</NButton>
          <NButton :disabled="selectedFiles.length === 0" type="error" ghost @click="showDeleteDialog = true">删除</NButton>
          <NButton :disabled="selectedFiles.length === 0" @click="downloadSelectedFiles">
            <template #icon>
              <NIcon>
                <Download />
              </NIcon>
            </template>
            下载
          </NButton>
        </div>

        <FileBrowserContent :files="fileStore.displayFiles" :loading="fileStore.loading"
          :selected-names="fileStore.selectedNames" :view-mode="fileStore.viewMode" :format-file-size="formatFileSize"
          :format-modify-time="formatModifyTime" @click-file="handleFileClick" @context-blank="openBlankContextMenu"
          @context-file="openFileContextMenu" @open-file="openFile" @select-names="handleSelectNames" />

        <NCard v-if="selectedFile" size="small" class="details-panel rounded-[16px]"
          :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.56)]' : 'bg-[rgba(255,255,255,0.84)]'">
          <div class="flex min-w-0 items-center gap-[12px] whitespace-nowrap">
            <span class="flex-none text-[12px]"
              :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.9)]' : 'text-[rgba(100,116,139,0.92)]'">当前选择</span>
            <span class="truncate-line">{{ selectedFiles.length > 1 ? `已选 ${selectedFiles.length} 项` : selectedFile.filename
            }}</span>
            <span class="flex-none text-[12px]"
              :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.9)]' : 'text-[rgba(100,116,139,0.92)]'">{{
                selectedFile.isDirectory ? '目录' : formatFileSize(selectedFile.size) }}</span>
            <span class="flex-none text-[12px]"
              :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.9)]' : 'text-[rgba(100,116,139,0.92)]'">{{
                formatModifyTime(selectedFile.modifyTime) }}</span>
          </div>
        </NCard>
      </div>
    </div>

    <NDropdown v-if="contextMenu" placement="bottom-start" trigger="manual" show :x="contextMenu.x" :y="contextMenu.y"
      :options="contextMenuOptions" @clickoutside="closeContextMenu" @select="handleContextMenuSelect" />

    <FileNameDialog v-model:show="showCreateDialog" :title="createDialogMode === 'directory' ? '新建目录' : '新建文件'"
      :value="newItemName" @update:value="(value) => (newItemName = value)" @confirm="confirmCreate" />

    <FileNameDialog v-model:show="showRenameDialog" title="重命名" :value="renameValue"
      @update:value="(value) => (renameValue = value)" @confirm="confirmRename" />

    <NModal v-model:show="showDeleteDialog" preset="dialog" title="确认删除" positive-text="删除" negative-text="取消"
      :positive-button-props="{ loading: deletingFiles }"
      @positive-click="confirmDelete" @negative-click="showDeleteDialog = false">
      删除 {{ selectedFiles.length > 1 ? `这 ${selectedFiles.length} 个项目` : '`' + (selectedFile?.filename ?? '') + '`' }}
      后不可恢复。
    </NModal>
  </div>
</template>

<style scoped>
.path-editor :deep(.n-input) {
  width: 100%;
}

.details-panel :deep(.n-card__content) {
  padding: 8px 12px;
}
</style>
