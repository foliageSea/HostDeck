<script setup lang="ts">
import { computed, onMounted, ref, type ComponentPublicInstance } from 'vue'
import { useLocalStorage } from '@vueuse/core'
import { Upload } from '@vicons/carbon'
import { filesApi, type FileItem } from '@/api/files'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { createFileStore, type FileSortKey } from '@/stores/file'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'
import { resolve } from '@/utils/path'
import FileActionToolbar from './components/FileActionToolbar.vue'
import FileBrowserContent from './components/FileBrowserContent.vue'
import FileCompressDialog from './components/FileCompressDialog.vue'
import FileDeleteDialog from './components/FileDeleteDialog.vue'
import FileExtractDialog from './components/FileExtractDialog.vue'
import FileFavoriteSidebar from './components/FileFavoriteSidebar.vue'
import FileNameDialog from './components/FileNameDialog.vue'
import FileNavigationToolbar from './components/FileNavigationToolbar.vue'
import FilePathToolbar from './components/FilePathToolbar.vue'
import FilePermissionDialog from './components/FilePermissionDialog.vue'
import FilePropertiesDialog from './components/FilePropertiesDialog.vue'
import FileSelectionDetails from './components/FileSelectionDetails.vue'
import { useFileClipboardOperations } from './composables/useFileClipboardOperations'
import { useFileDownloads } from './composables/useFileDownloads'
import { useFileUploads } from './composables/useFileUploads'
import { useRemoteFileTasks } from './composables/useRemoteFileTasks'
import {
  createPermissionMatrix,
  formatFileSize,
  formatModifyTime,
  getArchiveExtension,
  getExtractDirectoryName,
  getFileOpenCategory,
  getPermissionFromLongname,
  permissionMatrixToMode,
  permissionModeToMatrix,
  permissionToMode,
  type PermissionMatrix,
} from './utils'

const props = defineProps<{
  windowId?: string
  connectionId?: string
  host?: string
  path?: string
  port?: number
  username?: string
}>()

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const sshStore = useSshStore()
const FAVORITE_SIDEBAR_VISIBLE_STORAGE_KEY = 'host-deck:files:favorite-sidebar-visible'
const FAVORITE_SIDEBAR_WIDTH_STORAGE_KEY = 'host-deck:files:favorite-sidebar-width'

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
const extractTargetName = ref('')
const compressTargetName = ref('')
const compressFormat = ref<'tar.gz' | 'zip'>('tar.gz')
const editingPath = ref(false)
const showCreateDialog = ref(false)
const showRenameDialog = ref(false)
const showExtractDialog = ref(false)
const showCompressDialog = ref(false)
const showDeleteDialog = ref(false)
const showPropertiesDialog = ref(false)
const showPermissionDialog = ref(false)
const deletingFiles = ref(false)
const extractingArchive = ref(false)
const calculatingDirectorySize = ref(false)
const changingPermission = ref(false)
const propertiesFile = ref<FileItem | null>(null)
const propertiesItemPath = ref('')
const calculatedDirectorySize = ref<number | null>(null)
const permissionFile = ref<FileItem | null>(null)
const permissionItemPath = ref('')
const permissionRecursive = ref(false)
const contextMenu = ref<{
  type: 'file' | 'blank'
  x: number
  y: number
} | null>(null)
const isFavoriteSidebarVisible = useLocalStorage(FAVORITE_SIDEBAR_VISIBLE_STORAGE_KEY, false)
const favoriteSidebarWidth = useLocalStorage(FAVORITE_SIDEBAR_WIDTH_STORAGE_KEY, 252)

const selectedFile = computed(() => fileStore.selectedFile)
const selectedFiles = computed(() =>
  fileStore.files.filter((file) => fileStore.selectedNames.includes(file.filename)),
)
const { restoreRemoteTasks, startRemoteTask } = useRemoteFileTasks({
  getConnectionId: () => fileStore.connectionId,
  getCurrentPath: () => fileStore.currentPath,
  getWindowId: () => props.windowId,
  refreshFiles: () => fileStore.fetchFiles(),
})
const { canPasteToCurrentPath, clipboardPasteLabel, pasteClipboardItems, saveClipboard } =
  useFileClipboardOperations({
    getConnectionId: () => fileStore.connectionId,
    getHost: () => (props.host as string | undefined) ?? sshStore.host,
    getPort: () => (props.port as number | undefined) ?? sshStore.port,
    getUsername: () => (props.username as string | undefined) ?? sshStore.username,
    getCurrentPath: () => fileStore.currentPath,
    getFiles: () => fileStore.files,
    getSelectedFiles: () => selectedFiles.value,
    getWindowId: () => props.windowId,
    setSelectedNames: (names) => fileStore.setSelectedNames(names),
    refreshFiles: () => fileStore.fetchFiles(),
    startRemoteTask,
  })
const { downloadSelectedFiles } = useFileDownloads({
  getConnectionId: () => fileStore.connectionId,
  getCurrentPath: () => fileStore.currentPath,
  getSelectedFiles: () => selectedFiles.value,
})
const {
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
} = useFileUploads({
  getConnectionId: () => fileStore.connectionId,
  getCurrentPath: () => fileStore.currentPath,
  refreshFiles: () => fileStore.fetchFiles(),
})

function setFileInputRef(element: Element | ComponentPublicInstance | null) {
  fileInputRef.value = element instanceof HTMLInputElement ? element : null
}

function setDirectoryInputRef(element: Element | ComponentPublicInstance | null) {
  directoryInputRef.value = element instanceof HTMLInputElement ? element : null
}

const isCurrentPathFavorite = computed(() => fileStore.isFavoritePath(fileStore.currentPath))
const isCurrentPathPinned = computed(() => desktopStore.isDirectoryPinned(fileStore.currentPath))
const trimmedSearch = computed(() => fileStore.search.trim())
const hasSearch = computed(() => trimmedSearch.value.length > 0)
const searchResultHint = computed(() => {
  if (!hasSearch.value) {
    return ''
  }

  const resultCount = fileStore.displayFiles.length
  const totalCount = fileStore.files.filter(
    (file) => file.filename !== '.' && file.filename !== '..',
  ).length
  return resultCount > 0
    ? `搜索“${trimmedSearch.value}”：找到 ${resultCount} 项，共 ${totalCount} 项`
    : `未找到匹配“${trimmedSearch.value}”的文件或目录`
})
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
const permissionMatrix = ref<PermissionMatrix>(createPermissionMatrix())
const canExtractSelectedArchive = computed(() => {
  const file = selectedFile.value
  return (
    selectedFiles.value.length === 1 &&
    file !== null &&
    !file.isDirectory &&
    getArchiveExtension(file.filename) !== null
  )
})
const canCompressSelectedItem = computed(
  () => selectedFiles.value.length === 1 && selectedFile.value !== null,
)
const contextMenuOptions = computed(() => {
  if (contextMenu.value?.type === 'file') {
    const options = [
      {
        label: '打开',
        key: 'open',
        disabled: selectedFiles.value.length !== 1,
      },
      {
        label: '使用文本编辑器打开',
        key: 'open-in-editor',
        disabled: !canOpenSelectedFileInEditor.value,
      },
      {
        label: '解压缩',
        key: 'extract',
        disabled: !canExtractSelectedArchive.value,
      },
      {
        label: '压缩',
        key: 'compress',
        disabled: !canCompressSelectedItem.value,
      },
      {
        label: '下载',
        key: 'download',
        disabled: selectedFiles.value.length === 0,
      },
      {
        label: '复制',
        key: 'copy',
        disabled: selectedFiles.value.length === 0,
      },
      {
        label: '复制路径',
        key: 'copy-path',
        disabled: selectedFiles.value.length !== 1,
      },
      {
        label: '移动',
        key: 'move',
        disabled: selectedFiles.value.length === 0,
      },
      { type: 'divider', key: 'file-divider-1' },
      {
        label: '重命名',
        key: 'rename',
        disabled: selectedFiles.value.length !== 1,
      },
      {
        label: '删除',
        key: 'delete',
        disabled: selectedFiles.value.length === 0,
      },
      {
        label: '修改权限',
        key: 'chmod',
        disabled: selectedFiles.value.length !== 1,
      },
      {
        label: '属性',
        key: 'properties',
        disabled: selectedFiles.value.length !== 1,
      },
    ]

    if (selectedDirectoryPath.value) {
      options.splice(2, 0, {
        label: fileStore.isFavoritePath(selectedDirectoryPath.value)
          ? '取消收藏该目录'
          : '收藏该目录',
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
    { label: '上传文件', key: 'upload', disabled: isUploading.value },
    { label: '上传目录', key: 'upload-directory', disabled: isUploading.value },
    {
      label: clipboardPasteLabel.value,
      key: 'paste',
      disabled: !canPasteToCurrentPath.value,
    },
    { label: '复制当前路径', key: 'copy-current-path' },
    { type: 'divider', key: 'blank-divider-1' },
    { label: '刷新', key: 'refresh' },
    {
      label: '全选',
      key: 'select-all',
      disabled: fileStore.displayFiles.length === 0,
    },
    { type: 'divider', key: 'blank-divider-2' },
    {
      label: isCurrentPathFavorite.value ? '取消收藏当前目录' : '收藏当前目录',
      key: 'toggle-current-favorite',
    },
    {
      label: isCurrentPathPinned.value ? '从桌面移除当前目录' : '将当前目录钉到桌面',
      key: 'toggle-current-directory-pin',
    },
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
const propertiesPath = computed(() => (propertiesFile.value ? propertiesItemPath.value : ''))
const propertiesPermission = computed(() =>
  getPermissionFromLongname(propertiesFile.value?.longname),
)
const permissionCurrentText = computed(() =>
  getPermissionFromLongname(permissionFile.value?.longname),
)
const isPermissionParsed = computed(() => permissionCurrentText.value !== '-')
const hasSpecialPermissionBits = computed(() => /[sStT]/.test(permissionCurrentText.value))
const permissionMode = computed(() => permissionMatrixToMode(permissionMatrix.value))
const propertiesSizeText = computed(() => {
  const file = propertiesFile.value
  if (!file) {
    return '-'
  }

  if (!file.isDirectory) {
    return `${formatFileSize(file.size)} (${file.size} 字节)`
  }

  if (calculatedDirectorySize.value === null) {
    return '未计算'
  }

  return `${formatFileSize(calculatedDirectorySize.value)} (${calculatedDirectorySize.value} 字节)`
})

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

function applyPermissionMode(mode: string) {
  permissionMatrix.value = permissionModeToMatrix(mode)
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

async function copyPathToClipboard(path: string, successMessage: string) {
  try {
    await navigator.clipboard.writeText(path)
    getUiApi().message.success(successMessage)
  } catch (error) {
    console.error('Failed to copy file path', error)
    getUiApi().message.error('复制路径失败。')
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

  if (key === 'extract') {
    openExtractDialog()
    return
  }

  if (key === 'compress') {
    openCompressDialog()
    return
  }

  if (key === 'copy') {
    saveClipboard('copy')
    return
  }

  if (key === 'copy-path' && selectedFile.value) {
    void copyPathToClipboard(
      resolve(fileStore.currentPath, selectedFile.value.filename),
      '已复制路径。',
    )
    return
  }

  if (key === 'properties') {
    openPropertiesDialog()
    return
  }

  if (key === 'chmod') {
    openPermissionDialog()
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

  if (key === 'upload-directory') {
    triggerDirectoryUpload()
    return
  }

  if (key === 'paste') {
    void pasteClipboardItems()
    return
  }

  if (key === 'copy-current-path') {
    void copyPathToClipboard(fileStore.currentPath, '已复制当前路径。')
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
  if (file.isDirectory || !fileStore.connectionId) {
    return
  }

  desktopStore.openWindow(
    'editor',
    {
      connectionId: fileStore.connectionId,
      path: resolve(fileStore.currentPath, file.filename),
      title: file.filename,
    },
    { parentId: props.windowId },
  )
}

async function openFile(file: FileItem) {
  closeContextMenu()
  fileStore.selectFile(file)
  if (!file.isDirectory) {
    const category = getFileOpenCategory(file.filename)

    if (category === 'editable') {
      openFileInEditor(file)
      return
    }

    if (category === 'image' || category === 'video') {
      const playlist = fileStore.files
        .filter((item) => !item.isDirectory)
        .filter((item) => ['image', 'video'].includes(getFileOpenCategory(item.filename)))
        .map((item) => {
          const itemCategory = getFileOpenCategory(item.filename)
          return {
            filename: item.filename,
            path: resolve(fileStore.currentPath, item.filename),
            type: itemCategory === 'video' ? 'video' : 'image',
          }
        })

      desktopStore.openWindow(
        'media-viewer',
        {
          connectionId: fileStore.connectionId,
          path: resolve(fileStore.currentPath, file.filename),
          playlist,
          title: file.filename,
        },
        { parentId: props.windowId },
      )
    }

    return
  }

  await fileStore.navigateTo(file.filename)
  clearSearch()
  syncPathInput()
}

async function submitPath() {
  const targetPath = resolve(fileStore.currentPath, currentPathInput.value)
  if (targetPath === fileStore.currentPath) {
    syncPathInput()
    editingPath.value = false
    return
  }

  await fileStore.navigateTo(targetPath)
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

function updateSortKey(value: string) {
  fileStore.setSortKey(value as FileSortKey)
}

function clearSearch() {
  fileStore.search = ''
}

function handleCreateSelect(key: string | number) {
  if (key === 'directory' || key === 'file') {
    openCreate(key)
  }
}

function handleUploadSelect(key: string | number) {
  if (key === 'file') {
    triggerUpload()
    return
  }

  if (key === 'directory') {
    triggerDirectoryUpload()
  }
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
  if (!fileStore.connectionId || !newItemName.value.trim()) {
    return
  }

  const nextPath = resolve(fileStore.currentPath, newItemName.value.trim())

  try {
    if (createDialogMode.value === 'directory') {
      await filesApi.mkdir(fileStore.connectionId, nextPath)
    } else {
      await filesApi.writeFile(fileStore.connectionId, nextPath, '')
    }

    showCreateDialog.value = false
    await fileStore.fetchFiles()
    getUiApi().message.success(
      createDialogMode.value === 'directory' ? '目录已创建。' : '文件已创建。',
    )
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

function openExtractDialog() {
  if (!canExtractSelectedArchive.value || !selectedFile.value) {
    return
  }

  extractTargetName.value = getExtractDirectoryName(selectedFile.value.filename)
  showExtractDialog.value = true
}

function openCompressDialog() {
  if (!canCompressSelectedItem.value || !selectedFile.value) return
  compressFormat.value = 'tar.gz'
  compressTargetName.value = `${selectedFile.value.filename}.tar.gz`
  showCompressDialog.value = true
}

function updateCompressFormat(format: string) {
  if (format !== 'tar.gz' && format !== 'zip') return
  compressFormat.value = format
  if (!selectedFile.value) return

  const extension = format === 'zip' ? '.zip' : '.tar.gz'
  const currentExtension = compressTargetName.value.endsWith('.zip')
    ? '.zip'
    : compressTargetName.value.endsWith('.tar.gz')
      ? '.tar.gz'
      : ''
  const baseName = currentExtension
    ? compressTargetName.value.slice(0, -currentExtension.length)
    : selectedFile.value.filename
  compressTargetName.value = `${baseName}${extension}`
}

function openPropertiesDialog() {
  if (selectedFiles.value.length !== 1 || !selectedFile.value) {
    return
  }

  propertiesFile.value = selectedFile.value
  propertiesItemPath.value = resolve(fileStore.currentPath, selectedFile.value.filename)
  calculatedDirectorySize.value = null
  showPropertiesDialog.value = true
}

function openPermissionDialog(file = selectedFile.value, path?: string) {
  if (!file) {
    return
  }

  permissionFile.value = file
  permissionItemPath.value = path ?? resolve(fileStore.currentPath, file.filename)
  permissionRecursive.value = false

  const currentMode = permissionToMode(getPermissionFromLongname(file.longname))
  if (currentMode) {
    applyPermissionMode(currentMode)
  } else {
    permissionMatrix.value = createPermissionMatrix()
  }

  showPermissionDialog.value = true
}

async function refreshAfterPermissionChange(filename: string) {
  await fileStore.fetchFiles()
  fileStore.setSelectedNames([filename])

  const refreshedFile = fileStore.files.find((file) => file.filename === filename)
  if (!refreshedFile) {
    return
  }

  permissionFile.value = refreshedFile
  if (propertiesFile.value?.filename === filename) {
    propertiesFile.value = refreshedFile
  }
}

function getPermissionErrorMessage(error: unknown, recursive: boolean) {
  if (error instanceof Error && error.message) {
    return error.message
  }

  return recursive ? '递归权限修改失败。' : '权限修改失败。'
}

async function applyPermissionChange() {
  if (!fileStore.connectionId || !permissionFile.value || changingPermission.value) {
    return
  }

  const targetFile = permissionFile.value
  const targetPath = permissionItemPath.value
  const mode = permissionMode.value
  const recursive = permissionRecursive.value && targetFile.isDirectory

  changingPermission.value = true
  try {
    await filesApi.chmod(fileStore.connectionId, targetPath, mode, recursive)
    showPermissionDialog.value = false
    await refreshAfterPermissionChange(targetFile.filename)
    getUiApi().message.success(recursive ? '递归权限修改成功。' : '权限修改成功。')
  } catch (error) {
    console.error('Failed to change file permission', error)
    getUiApi().message.error(getPermissionErrorMessage(error, recursive))
  } finally {
    changingPermission.value = false
  }
}

function confirmPermissionChange() {
  const targetFile = permissionFile.value
  if (!targetFile) {
    return
  }

  if (!permissionRecursive.value || !targetFile.isDirectory) {
    void applyPermissionChange()
    return
  }

  getUiApi().dialog.warning({
    title: '确认递归修改权限',
    content: `将递归修改 ${permissionItemPath.value} 下所有文件和子目录权限，此操作可能影响程序运行或安全策略。是否继续？`,
    positiveText: '继续修改',
    negativeText: '取消',
    onPositiveClick: () => {
      void applyPermissionChange()
    },
  })
}

async function calculateDirectorySize() {
  if (
    !fileStore.connectionId ||
    !propertiesFile.value?.isDirectory ||
    calculatingDirectorySize.value
  ) {
    return
  }

  calculatingDirectorySize.value = true
  try {
    const result = await filesApi.directorySize(fileStore.connectionId, propertiesPath.value)
    calculatedDirectorySize.value = result.size
  } catch (error) {
    console.error('Failed to calculate directory size', error)
    getUiApi().message.error('目录大小计算失败。')
  } finally {
    calculatingDirectorySize.value = false
  }
}

async function confirmExtract() {
  if (
    !fileStore.connectionId ||
    !selectedFile.value ||
    !canExtractSelectedArchive.value ||
    extractingArchive.value
  ) {
    return
  }

  const targetName = extractTargetName.value.trim()
  if (!targetName) {
    getUiApi().message.error('请输入解压目录名称。')
    return
  }

  const task = await startRemoteTask('extract', [
    {
      sourcePath: resolve(fileStore.currentPath, selectedFile.value.filename),
      targetPath: resolve(fileStore.currentPath, targetName),
    },
  ])
  if (task) {
    showExtractDialog.value = false
    fileStore.setSelectedNames([targetName])
  }
}

async function confirmCompress() {
  if (!fileStore.connectionId || !selectedFile.value || !canCompressSelectedItem.value) {
    return
  }

  const targetName = compressTargetName.value.trim()
  if (!targetName) {
    getUiApi().message.error('请输入压缩文件名称。')
    return
  }

  const extension = compressFormat.value === 'zip' ? '.zip' : '.tar.gz'
  if (!targetName.toLowerCase().endsWith(extension)) {
    getUiApi().message.error(`压缩文件名称必须以 ${extension} 结尾。`)
    return
  }

  const task = await startRemoteTask('compress', [
    {
      sourcePath: resolve(fileStore.currentPath, selectedFile.value.filename),
      targetPath: resolve(fileStore.currentPath, targetName),
    },
  ])
  if (task) {
    showCompressDialog.value = false
    fileStore.setSelectedNames([targetName])
  }
}

async function confirmRename() {
  if (!fileStore.connectionId || !selectedFile.value || !renameValue.value.trim()) {
    return
  }

  try {
    await filesApi.rename(
      fileStore.connectionId,
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
  if (!fileStore.connectionId || selectedFiles.value.length === 0 || deletingFiles.value) {
    return
  }

  const task = await startRemoteTask(
    'delete',
    selectedFiles.value.map((file) => ({
      sourcePath: resolve(fileStore.currentPath, file.filename),
    })),
  )
  if (task) {
    showDeleteDialog.value = false
    fileStore.clearSelection()
  }
}

function openTerminalHere() {
  const currentConnectionId = props.connectionId ?? sshStore.connectionId
  desktopStore.openWindow(
    'terminal',
    {
      connectionId: currentConnectionId ?? undefined,
      cwd: fileStore.currentPath,
      host: props.host ?? sshStore.host,
      title: `终端 · ${fileStore.currentPath}`,
      username: props.username ?? sshStore.username,
    },
    { parentId: props.windowId },
  )
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

  if (
    (event.ctrlKey || event.metaKey) &&
    event.key.toLowerCase() === 'c' &&
    fileStore.hasSelection
  ) {
    event.preventDefault()
    closeContextMenu()
    saveClipboard('copy')
    return
  }

  if (
    (event.ctrlKey || event.metaKey) &&
    event.key.toLowerCase() === 'x' &&
    fileStore.hasSelection
  ) {
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
  await restoreRemoteTasks()
})
</script>

<template>
  <div
    class="flex h-full flex-col gap-[14px] p-[16px] outline-none"
    :class="
      settingsStore.isDark
        ? 'bg-[linear-gradient(180deg,rgba(15,23,42,0.14),rgba(15,23,42,0.04))]'
        : 'bg-[linear-gradient(180deg,rgba(255,255,255,0.68),rgba(226,232,240,0.34))]'
    "
    tabindex="0"
    @keydown="handleKeydown"
    @click.self="fileStore.clearSelection()"
    @dragenter.prevent="handleUploadDragEnter"
    @dragover.prevent
    @dragleave.prevent="handleUploadDragLeave"
    @drop.prevent="handleUploadDrop"
  >
    <input :ref="setFileInputRef" type="file" multiple hidden @change="handleUploadChange" />
    <input
      :ref="setDirectoryInputRef"
      type="file"
      multiple
      webkitdirectory=""
      hidden
      @change="handleDirectoryUploadChange"
    />

    <FileNavigationToolbar
      v-model:search="fileStore.search"
      v-model:view-mode="fileStore.viewMode"
      :can-go-back="fileStore.backHistory.length > 0"
      :can-go-forward="fileStore.forwardHistory.length > 0"
      :sort-direction="fileStore.sortDirection"
      :sort-key="fileStore.sortKey"
      @navigate-back="navigateBack"
      @navigate-forward="navigateForward"
      @navigate-up="navigateUp"
      @refresh="fileStore.fetchFiles()"
      @toggle-sort-direction="fileStore.toggleSortDirection()"
      @update:sort-key="updateSortKey"
    />

    <div class="flex min-h-0 flex-1 gap-[14px]">
      <FileFavoriteSidebar
        v-model:width="favoriteSidebarWidth"
        :connection-id="fileStore.connectionId"
        :current-path="fileStore.currentPath"
        :favorite-paths="fileStore.favoritePaths"
        :visible="isFavoriteSidebarVisible"
        @navigate="navigateToPath"
        @remove="removeFavoritePath"
        @toggle-visibility="toggleFavoriteSidebar"
      />

      <div class="flex min-h-0 min-w-0 flex-1 flex-col gap-[14px]">
        <FilePathToolbar
          v-model:current-path-input="currentPathInput"
          :breadcrumbs="breadcrumbs"
          :editing-path="editingPath"
          :favorite-paths="fileStore.favoritePaths"
          :is-current-path-favorite="isCurrentPathFavorite"
          :is-current-path-pinned="isCurrentPathPinned"
          @navigate="navigateToPath"
          @open-terminal="openTerminalHere"
          @remove-favorite="removeFavoritePath"
          @start-editing="startPathEditing"
          @stop-editing="stopPathEditing"
          @submit-path="submitPath"
          @toggle-favorite="toggleCurrentFavorite"
          @toggle-pin="toggleCurrentDesktopPin"
        />

        <FileActionToolbar
          :can-compress="canCompressSelectedItem"
          :can-extract="canExtractSelectedArchive"
          :is-uploading="isUploading"
          :selected-count="selectedFiles.length"
          @compress="openCompressDialog"
          @create="handleCreateSelect"
          @delete="showDeleteDialog = true"
          @download="downloadSelectedFiles"
          @extract="openExtractDialog"
          @permission="openPermissionDialog()"
          @rename="openRenameDialog"
          @upload="handleUploadSelect"
        />

        <div
          v-if="hasSearch"
          class="app-radius-surface flex flex-wrap items-center justify-between gap-[10px] rounded-[16px] border px-[14px] py-[10px] shadow-[0_12px_28px_rgba(37,99,235,0.12)]"
          :class="
            settingsStore.isDark
              ? 'border-[rgba(96,165,250,0.42)] bg-[rgba(30,64,175,0.24)] text-[rgba(219,234,254,0.98)]'
              : 'border-[rgba(37,99,235,0.3)] bg-[rgba(219,234,254,0.86)] text-[rgba(30,64,175,0.98)]'
          "
        >
          <div class="flex min-w-0 items-center gap-[10px] text-[13px] font-600">
            <span class="h-[8px] w-[8px] flex-none rounded-full bg-[var(--app-primary-color)]" />
            <span class="truncate-line">{{ searchResultHint }}</span>
          </div>
          <NButton quaternary size="small" @click="clearSearch"> 清除搜索 </NButton>
        </div>

        <div class="relative min-h-0 flex flex-1">
          <FileBrowserContent
            :files="fileStore.displayFiles"
            :empty-description="hasSearch ? '没有找到匹配的文件或目录' : undefined"
            :loading="fileStore.loading"
            :selected-names="fileStore.selectedNames"
            :view-mode="fileStore.viewMode"
            :format-file-size="formatFileSize"
            :format-modify-time="formatModifyTime"
            @click-file="handleFileClick"
            @context-blank="openBlankContextMenu"
            @context-file="openFileContextMenu"
            @open-file="openFile"
            @select-names="handleSelectNames"
          />

          <div
            v-if="isDraggingUpload"
            class="app-radius-surface pointer-events-none absolute inset-[4px] z-20 flex items-center justify-center rounded-[18px] border-2 border-dashed border-[var(--app-primary-border-strong)] bg-[var(--app-primary-soft)] p-[24px] backdrop-blur-[6px]"
          >
            <div
              class="flex max-w-[420px] flex-col items-center gap-[10px] text-center text-[var(--app-primary-color)]"
            >
              <NIcon size="42">
                <Upload />
              </NIcon>
              <div class="text-[18px] font-700">
                {{ isUploading ? '当前有传输任务进行中' : '释放以上传到当前目录' }}
              </div>
              <div class="text-[13px] opacity-80">
                {{
                  isUploading
                    ? '请等待当前任务完成后再试'
                    : `支持多个文件或文件夹，目标位置：${fileStore.currentPath}`
                }}
              </div>
            </div>
          </div>
        </div>

        <FileSelectionDetails
          :selected-count="selectedFiles.length"
          :selected-file="selectedFile"
        />
      </div>
    </div>

    <NDropdown
      v-if="contextMenu"
      placement="bottom-start"
      trigger="manual"
      show
      :x="contextMenu.x"
      :y="contextMenu.y"
      :options="contextMenuOptions"
      @clickoutside="closeContextMenu"
      @select="handleContextMenuSelect"
    />

    <FileNameDialog
      v-model:show="showCreateDialog"
      :title="createDialogMode === 'directory' ? '新建目录' : '新建文件'"
      :value="newItemName"
      @update:value="(value) => (newItemName = value)"
      @confirm="confirmCreate"
    />

    <FileNameDialog
      v-model:show="showRenameDialog"
      title="重命名"
      :value="renameValue"
      @update:value="(value) => (renameValue = value)"
      @confirm="confirmRename"
    />

    <FileExtractDialog
      v-model:show="showExtractDialog"
      v-model:target-name="extractTargetName"
      :filename="selectedFile?.filename ?? ''"
      :loading="extractingArchive"
      @confirm="confirmExtract"
    />

    <FileCompressDialog
      v-model:show="showCompressDialog"
      v-model:target-name="compressTargetName"
      :filename="selectedFile?.filename ?? ''"
      :format="compressFormat"
      @confirm="confirmCompress"
      @update:format="updateCompressFormat"
    />

    <FilePropertiesDialog
      v-model:show="showPropertiesDialog"
      :calculating-directory-size="calculatingDirectorySize"
      :directory-size="calculatedDirectorySize"
      :file="propertiesFile"
      :path="propertiesPath"
      :permission="propertiesPermission"
      :size-text="propertiesSizeText"
      @calculate-directory-size="calculateDirectorySize"
      @edit-permission="openPermissionDialog"
    />

    <FilePermissionDialog
      v-model:show="showPermissionDialog"
      v-model:matrix="permissionMatrix"
      v-model:recursive="permissionRecursive"
      :changing="changingPermission"
      :current-permission="permissionCurrentText"
      :file="permissionFile"
      :has-special-permission-bits="hasSpecialPermissionBits"
      :is-permission-parsed="isPermissionParsed"
      :mode="permissionMode"
      :path="permissionItemPath"
      @apply-preset="applyPermissionMode"
      @confirm="confirmPermissionChange"
    />

    <FileDeleteDialog
      v-model:show="showDeleteDialog"
      :deleting="deletingFiles"
      :selected-count="selectedFiles.length"
      :selected-filename="selectedFile?.filename"
      @confirm="confirmDelete"
    />
  </div>
</template>
