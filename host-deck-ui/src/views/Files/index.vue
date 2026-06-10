<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
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
import { createFileStore, type FileSortKey } from '@/stores/file'
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
const FAVORITE_SIDEBAR_VISIBLE_STORAGE_KEY = 'host-deck:files:favorite-sidebar-visible'

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
const editingPath = ref(false)
const showCreateDialog = ref(false)
const showRenameDialog = ref(false)
const showExtractDialog = ref(false)
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
const fileInputRef = ref<HTMLInputElement | null>(null)
const directoryInputRef = ref<HTMLInputElement | null>(null)
const contextMenu = ref<{
  type: 'file' | 'blank'
  x: number
  y: number
} | null>(null)
const isFavoriteSidebarVisible = useLocalStorage(FAVORITE_SIDEBAR_VISIBLE_STORAGE_KEY, false)

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
  return Boolean(
    payload && payload.entries.length > 0 && payload.connectionKey === currentConnectionKey.value,
  )
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
const archiveExtensions = [
  '.tar.gz',
  '.tar.bz2',
  '.tar.xz',
  '.tgz',
  '.tbz2',
  '.txz',
  '.tar',
  '.zip',
]
const createOptions = [
  { label: '新建目录', key: 'directory' },
  { label: '新建文件', key: 'file' },
]
const sortOptions: { label: string; value: FileSortKey }[] = [
  { label: '名称', value: 'name' },
  { label: '大小', value: 'size' },
  { label: '修改时间', value: 'modifyTime' },
]
const uploadOptions = computed(() => [
  { label: '上传文件', key: 'file', disabled: isUploading.value },
  { label: '上传目录', key: 'directory', disabled: isUploading.value },
])
type PermissionSubject = 'owner' | 'group' | 'others'
type PermissionAction = 'read' | 'write' | 'execute'
type PermissionMatrix = Record<PermissionSubject, Record<PermissionAction, boolean>>

const permissionSubjects: { key: PermissionSubject; label: string }[] = [
  { key: 'owner', label: '所有者' },
  { key: 'group', label: '用户组' },
  { key: 'others', label: '其他人' },
]
const permissionActions: { key: PermissionAction; label: string }[] = [
  { key: 'read', label: '读取' },
  { key: 'write', label: '写入' },
  { key: 'execute', label: '执行' },
]
const permissionPresets = [
  { label: '普通文件 644', mode: '644' },
  { label: '可执行/目录 755', mode: '755' },
  { label: '私密文件 600', mode: '600' },
  { label: '私密目录 700', mode: '700' },
]
const permissionMatrix = ref(createPermissionMatrix())
const canExtractSelectedArchive = computed(() => {
  const file = selectedFile.value
  return (
    selectedFiles.value.length === 1 &&
    file !== null &&
    !file.isDirectory &&
    getArchiveExtension(file.filename) !== null
  )
})
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
const permissionMode = computed(() => getModeFromPermissionMatrix())
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

function getArchiveExtension(filename: string) {
  const lowerName = filename.toLowerCase()
  return archiveExtensions.find((extension) => lowerName.endsWith(extension)) ?? null
}

function getExtractDirectoryName(filename: string) {
  const extension = getArchiveExtension(filename)
  if (!extension) {
    return filename
  }

  const baseName = filename.slice(0, filename.length - extension.length)
  return baseName || filename
}

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

function getPermissionFromLongname(longname?: string) {
  const permission = longname?.trim().split(/\s+/)[0]
  return permission && /^[dlpscb-][rwxStTs-]{9}$/.test(permission) ? permission : '-'
}

function createPermissionMatrix(): PermissionMatrix {
  return {
    owner: { read: false, write: false, execute: false },
    group: { read: false, write: false, execute: false },
    others: { read: false, write: false, execute: false },
  }
}

function getModeFromPermissionMatrix() {
  return permissionSubjects
    .map(({ key }) => {
      const value = permissionMatrix.value[key]
      return ((value.read ? 4 : 0) + (value.write ? 2 : 0) + (value.execute ? 1 : 0)).toString()
    })
    .join('')
}

function applyPermissionMode(mode: string) {
  const normalizedMode = mode.length === 4 ? mode.slice(1) : mode
  const nextMatrix = createPermissionMatrix()

  permissionSubjects.forEach(({ key }, index) => {
    const digit = Number(normalizedMode[index] ?? '0')
    nextMatrix[key] = {
      read: (digit & 4) !== 0,
      write: (digit & 2) !== 0,
      execute: (digit & 1) !== 0,
    }
  })

  permissionMatrix.value = nextMatrix
}

function getModeFromPermission(permission: string) {
  if (!/^[dlpscb-][rwxStTs-]{9}$/.test(permission)) {
    return null
  }

  const value = permission.slice(1)
  const digits = [0, 3, 6].map((start) => {
    const read = value[start] === 'r' ? 4 : 0
    const write = value[start + 1] === 'w' ? 2 : 0
    const execute = /[xst]/.test(value[start + 2] ?? '') ? 1 : 0
    return (read + write + execute).toString()
  })

  return digits.join('')
}

function setPermissionChecked(
  subject: PermissionSubject,
  action: PermissionAction,
  checked: boolean,
) {
  permissionMatrix.value[subject][action] = checked
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
  if (!fileStore.connectionId) {
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
          ? filesApi.rename(fileStore.connectionId as string, entry.path, nextPath)
          : filesApi.copy(fileStore.connectionId as string, entry.path, nextPath)
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

  desktopStore.openWindow('editor', {
    connectionId: fileStore.connectionId,
    path: resolve(fileStore.currentPath, file.filename),
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
        connectionId: fileStore.connectionId,
        path: resolve(fileStore.currentPath, file.filename),
        playlist,
        title: file.filename,
      })
    }

    return
  }

  await fileStore.navigateTo(file.filename)
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

  const currentMode = getModeFromPermission(getPermissionFromLongname(file.longname))
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

  extractingArchive.value = true
  try {
    await filesApi.extract(
      fileStore.connectionId,
      resolve(fileStore.currentPath, selectedFile.value.filename),
      resolve(fileStore.currentPath, targetName),
    )
    showExtractDialog.value = false
    await fileStore.fetchFiles()
    fileStore.setSelectedNames([targetName])
    getUiApi().message.success('解压成功。')
  } catch (error) {
    console.error('Failed to extract archive', error)
    getUiApi().message.error(error instanceof Error ? error.message : '解压失败。')
  } finally {
    extractingArchive.value = false
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

  deletingFiles.value = true
  try {
    await Promise.all(
      selectedFiles.value.map((file) =>
        filesApi.delete(
          fileStore.connectionId as string,
          resolve(fileStore.currentPath, file.filename),
        ),
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
  if (!fileStore.connectionId || selectedFiles.value.length === 0) {
    return
  }

  const filesToDownload = [...selectedFiles.value]
  const fileConnectionId = fileStore.connectionId
  const batchPath = fileStore.currentPath
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
    if (isUploadCancelled(error) || uploadCenterStore.isBatchCancelled(batchId)) {
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
    uploadCenterStore.markBatchError(batchId, error instanceof Error ? error.message : '下载失败。')
    console.error('Failed to download selection', error)
    getUiApi().message.error('下载失败。')
  } finally {
    uploadCenterStore.clearBatchController(batchId)
  }
}

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

function getUploadRelativePath(file: File) {
  return 'webkitRelativePath' in file && typeof file.webkitRelativePath === 'string'
    ? file.webkitRelativePath
    : file.name
}

function getUploadDirectory(relativePath: string) {
  const segments = relativePath.split('/').filter(Boolean)
  segments.pop()
  return segments.join('/')
}

function getUploadFilename(relativePath: string, file: File) {
  const segments = relativePath.split('/').filter(Boolean)
  return segments.at(-1) ?? file.name
}

async function ensureUploadDirectories(connectionId: string, relativePaths: string[]) {
  const directories = Array.from(
    new Set(relativePaths.map(getUploadDirectory).filter(Boolean)),
  ).sort((left, right) => left.split('/').length - right.split('/').length)

  for (const directory of directories) {
    try {
      await filesApi.mkdir(connectionId, resolve(fileStore.currentPath, directory))
    } catch {
      // Existing remote directories are fine; upload will still fail later if the path is unusable.
    }
  }
}

function isUploadCancelled(error: unknown) {
  return (
    typeof error === 'object' && error !== null && 'code' in error && error.code === 'ERR_CANCELED'
  )
}

function getDownloadProgress(loaded: number, total: number) {
  if (total <= 0) {
    return loaded > 0 ? 1 : 0
  }

  return Math.min(100, Math.round((Math.min(loaded, total) / total) * 100))
}

async function handleUploadChange(event: Event) {
  if (!fileStore.connectionId) {
    return
  }

  const input = event.target as HTMLInputElement
  const files = input.files
  if (!files || files.length === 0) {
    return
  }

  const selectedUploads = Array.from(files).map((file) => ({
    file,
    name: file.name,
    path: fileStore.currentPath,
    relativePath: file.name,
  }))
  const batchId = uploadCenterStore.createBatch(
    fileStore.connectionId,
    fileStore.currentPath,
    selectedUploads,
  )
  const controller = new AbortController()
  uploadCenterStore.clearBatchError(batchId)
  uploadCenterStore.registerBatchController(batchId, controller)

  let hasUploadedFiles = false

  try {
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
      formData.append('file', upload.file, upload.file.name)
      await filesApi.upload(
        fileStore.connectionId,
        fileStore.currentPath,
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

async function handleDirectoryUploadChange(event: Event) {
  if (!fileStore.connectionId) {
    return
  }

  const input = event.target as HTMLInputElement
  const files = input.files
  if (!files || files.length === 0) {
    return
  }

  const selectedUploads = Array.from(files).map((file) => {
    const relativePath = getUploadRelativePath(file)
    const directory = getUploadDirectory(relativePath)

    return {
      file,
      name: relativePath,
      path: directory ? resolve(fileStore.currentPath, directory) : fileStore.currentPath,
      relativePath,
    }
  })
  const batchId = uploadCenterStore.createBatch(
    fileStore.connectionId,
    fileStore.currentPath,
    selectedUploads,
  )
  const controller = new AbortController()
  uploadCenterStore.clearBatchError(batchId)
  uploadCenterStore.registerBatchController(batchId, controller)

  let hasUploadedFiles = false

  try {
    await ensureUploadDirectories(
      fileStore.connectionId,
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
        fileStore.connectionId,
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
        await fileStore.fetchFiles()
      }
      return
    }

    await fileStore.fetchFiles()
    getUiApi().message.success(`已上传目录中的 ${files.length} 个文件。`)
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
    const uploadingTask = batch?.tasks.find(
      (task) => task.status === 'uploading' || task.status === 'pending',
    )
    if (uploadingTask) {
      uploadCenterStore.updateTask(uploadingTask.id, {
        status: 'error',
      })
    }

    uploadCenterStore.markBatchError(
      batchId,
      error instanceof Error ? error.message : '上传目录失败。',
    )
    console.error('Failed to upload directory', error)
    getUiApi().message.error('上传目录失败。')
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
  >
    <input ref="fileInputRef" type="file" multiple hidden @change="handleUploadChange" />
    <input
      ref="directoryInputRef"
      type="file"
      multiple
      webkitdirectory=""
      hidden
      @change="handleDirectoryUploadChange"
    />

    <div class="flex flex-wrap items-center justify-between gap-[12px]">
      <NSpace align="center" wrap>
        <NTooltip>
          <template #trigger>
            <NButton
              quaternary
              round
              :disabled="fileStore.backHistory.length === 0"
              @click="navigateBack"
            >
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
            <NButton
              quaternary
              round
              :disabled="fileStore.forwardHistory.length === 0"
              @click="navigateForward"
            >
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
            <NButton quaternary round @click="navigateUp">
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
            <NButton quaternary round @click="fileStore.fetchFiles()">
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

      <div class="flex items-center gap-[8px]">
        <NInput
          v-model:value="fileStore.search"
          placeholder="搜索当前目录"
          clearable
          class="w-[min(240px,60vw)]"
        />
        <NSelect
          :value="fileStore.sortKey"
          :options="sortOptions"
          class="w-[116px] flex-none"
          @update:value="updateSortKey"
        />
        <NButton quaternary round @click="fileStore.toggleSortDirection()">
          {{ fileStore.sortDirection === 'asc' ? '升序' : '降序' }}
        </NButton>
        <div class="flex items-center gap-[8px]">
          <NTooltip>
            <template #trigger>
              <NButton
                quaternary
                round
                :type="fileStore.viewMode === 'list' ? 'primary' : 'default'"
                @click="fileStore.viewMode = 'list'"
              >
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
              <NButton
                quaternary
                round
                :type="fileStore.viewMode === 'grid' ? 'primary' : 'default'"
                @click="fileStore.viewMode = 'grid'"
              >
                <template #icon>
                  <NIcon>
                    <Grid />
                  </NIcon>
                </template>
              </NButton>
            </template>
            网格视图
          </NTooltip>
          <NPopover trigger="hover" placement="bottom-end">
            <template #trigger>
              <NButton quaternary round>
                <template #icon>
                  <NIcon>
                    <Help />
                  </NIcon>
                </template>
              </NButton>
            </template>
            <div
              class="flex flex-col gap-[6px] text-[12px]"
              :class="
                settingsStore.isDark
                  ? 'text-[rgba(226,232,240,0.96)]'
                  : 'text-[rgba(51,65,85,0.96)]'
              "
            >
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
        </div>
      </div>
    </div>

    <div class="flex min-h-0 flex-1 gap-[14px]">
      <FileFavoriteSidebar
        :current-path="fileStore.currentPath"
        :favorite-paths="fileStore.favoritePaths"
        :is-current-path-favorite="isCurrentPathFavorite"
        :visible="isFavoriteSidebarVisible"
        @navigate="navigateToPath"
        @remove="removeFavoritePath"
        @toggle-current-favorite="toggleCurrentFavorite"
        @toggle-visibility="toggleFavoriteSidebar"
      />

      <div class="flex min-h-0 min-w-0 flex-1 flex-col gap-[14px]">
        <div class="flex flex-wrap items-center justify-between gap-[12px]">
          <div
            v-if="!editingPath"
            class="min-w-[240px] flex-1 overflow-x-auto pb-[2px] app-scrollbar app-scrollbar-compact"
            :class="settingsStore.isDark ? 'app-scrollbar-dark' : 'app-scrollbar-light'"
          >
            <NBreadcrumb>
              <NBreadcrumbItem v-for="item in breadcrumbs" :key="item.path">
                <button
                  type="button"
                  class="btn-reset hover:text-[rgba(96,165,250,0.95)]"
                  @click="navigateToPath(item.path)"
                >
                  {{ item.label }}
                </button>
              </NBreadcrumbItem>
            </NBreadcrumb>
          </div>
          <div v-else class="path-editor min-w-[240px] flex-1">
            <NInput
              v-model:value="currentPathInput"
              placeholder="输入远程路径快速跳转"
              @keyup.enter="submitPath"
              @keyup.esc="stopPathEditing"
              @blur="stopPathEditing"
            />
          </div>

          <div class="flex flex-wrap items-center justify-end gap-[12px]">
            <NButton
              v-if="editingPath"
              quaternary
              size="small"
              round
              type="primary"
              @mousedown.prevent
              @click="submitPath"
              >跳转</NButton
            >
            <NTooltip v-else>
              <template #trigger>
                <NButton quaternary size="small" round @click="startPathEditing">
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
                <NButton
                  quaternary
                  size="small"
                  round
                  :type="isCurrentPathFavorite ? 'warning' : 'default'"
                  @click="toggleCurrentFavorite"
                >
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
                <NButton
                  quaternary
                  size="small"
                  round
                  :type="isCurrentPathPinned ? 'primary' : 'default'"
                  @click="toggleCurrentDesktopPin"
                >
                  <template #icon>
                    <NIcon>
                      <component :is="isCurrentPathPinned ? PinFilled : Pin" />
                    </NIcon>
                  </template>
                </NButton>
              </template>
              {{ isCurrentPathPinned ? '从桌面移除当前目录' : '将当前目录钉到桌面' }}
            </NTooltip>
            <NPopover
              v-if="fileStore.favoritePaths.length > 0"
              trigger="click"
              placement="bottom-end"
            >
              <template #trigger>
                <NButton quaternary size="small" round class="md:hidden">
                  <template #icon>
                    <NIcon>
                      <LocationStar />
                    </NIcon>
                  </template>
                </NButton>
              </template>
              <div class="w-[min(360px,72vw)]">
                <div
                  class="mb-[10px] text-[13px] font-600"
                  :class="
                    settingsStore.isDark
                      ? 'text-[rgba(226,232,240,0.96)]'
                      : 'text-[rgba(51,65,85,0.96)]'
                  "
                >
                  收藏目录
                </div>
                <NScrollbar
                  class="favorite-popover-scrollbar"
                  :class="!settingsStore.isDark && 'favorite-popover-scrollbar-light'"
                  style="max-height: 260px"
                >
                  <div class="flex flex-col gap-[6px] pr-[10px]">
                    <div
                      v-for="path in fileStore.favoritePaths"
                      :key="path"
                      class="flex min-w-0 items-center gap-[8px] rounded-[10px] py-[6px] pl-[10px] pr-[6px]"
                      :class="
                        settingsStore.isDark
                          ? 'bg-[rgba(15,23,42,0.5)]'
                          : 'bg-[rgba(241,245,249,0.92)]'
                      "
                    >
                      <button
                        type="button"
                        class="btn-reset truncate-line flex-1 text-left hover:text-[rgba(96,165,250,0.95)]"
                        :title="path"
                        @click="navigateToPath(path)"
                      >
                        {{ formatFavoritePath(path) }}
                      </button>
                      <NButton quaternary round size="tiny" @click.stop="removeFavoritePath(path)">
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
                <NButton quaternary size="small" round @click="openTerminalHere">
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

        <div class="flex w-full flex-wrap items-center justify-start gap-[12px]">
          <NDropdown trigger="click" :options="createOptions" @select="handleCreateSelect">
            <NButton quaternary round>
              <template #icon>
                <NIcon>
                  <FolderAdd />
                </NIcon>
              </template>
              新建
            </NButton>
          </NDropdown>
          <NDropdown trigger="click" :options="uploadOptions" @select="handleUploadSelect">
            <NButton quaternary round :disabled="isUploading" :loading="isUploading">
              <template #icon>
                <NIcon>
                  <Upload />
                </NIcon>
              </template>
              上传
            </NButton>
          </NDropdown>
          <NButton
            quaternary
            round
            :disabled="!canExtractSelectedArchive"
            @click="openExtractDialog"
            >解压缩</NButton
          >
          <NButton quaternary round :disabled="selectedFiles.length !== 1" @click="openRenameDialog"
            >重命名</NButton
          >
          <NButton
            quaternary
            round
            :disabled="selectedFiles.length !== 1"
            @click="openPermissionDialog()"
            >权限</NButton
          >
          <NButton
            quaternary
            round
            :disabled="selectedFiles.length === 0"
            type="error"
            @click="showDeleteDialog = true"
            >删除</NButton
          >
          <NButton
            quaternary
            round
            :disabled="selectedFiles.length === 0"
            @click="downloadSelectedFiles"
          >
            <template #icon>
              <NIcon>
                <Download />
              </NIcon>
            </template>
            下载
          </NButton>
        </div>

        <div
          v-if="hasSearch"
          class="flex flex-wrap items-center justify-between gap-[10px] rounded-[16px] border px-[14px] py-[10px] shadow-[0_12px_28px_rgba(37,99,235,0.12)]"
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
          <NButton quaternary round size="small" @click="clearSearch"> 清除搜索 </NButton>
        </div>

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

        <NCard
          v-if="selectedFile"
          size="small"
          class="details-panel rounded-[16px]"
          :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.56)]' : 'bg-[rgba(255,255,255,0.84)]'"
        >
          <div class="flex min-w-0 items-center gap-[12px] whitespace-nowrap">
            <span
              class="flex-none text-[12px]"
              :class="
                settingsStore.isDark
                  ? 'text-[rgba(148,163,184,0.9)]'
                  : 'text-[rgba(100,116,139,0.92)]'
              "
              >当前选择</span
            >
            <span class="truncate-line">{{
              selectedFiles.length > 1 ? `已选 ${selectedFiles.length} 项` : selectedFile.filename
            }}</span>
            <span
              class="flex-none text-[12px]"
              :class="
                settingsStore.isDark
                  ? 'text-[rgba(148,163,184,0.9)]'
                  : 'text-[rgba(100,116,139,0.92)]'
              "
              >{{ selectedFile.isDirectory ? '目录' : formatFileSize(selectedFile.size) }}</span
            >
            <span
              class="flex-none text-[12px]"
              :class="
                settingsStore.isDark
                  ? 'text-[rgba(148,163,184,0.9)]'
                  : 'text-[rgba(100,116,139,0.92)]'
              "
              >{{ formatModifyTime(selectedFile.modifyTime) }}</span
            >
          </div>
        </NCard>
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

    <NModal
      v-model:show="showExtractDialog"
      preset="card"
      title="解压缩"
      style="width: min(480px, calc(100vw - 24px))"
    >
      <NSpace vertical>
        <div
          :class="
            settingsStore.isDark ? 'text-[rgba(148,163,184,0.9)]' : 'text-[rgba(100,116,139,0.92)]'
          "
        >
          将 {{ selectedFile?.filename ?? '' }} 解压到当前目录下的新目录。
        </div>
        <NInput
          v-model:value="extractTargetName"
          placeholder="输入解压目录名称"
          @keyup.enter="confirmExtract"
        />
        <NSpace justify="end">
          <NButton quaternary round :disabled="extractingArchive" @click="showExtractDialog = false"
            >取消</NButton
          >
          <NButton
            quaternary
            round
            type="primary"
            :loading="extractingArchive"
            @click="confirmExtract"
            >解压</NButton
          >
        </NSpace>
      </NSpace>
    </NModal>

    <NModal
      v-model:show="showPropertiesDialog"
      preset="card"
      title="属性"
      style="width: min(560px, calc(100vw - 24px))"
    >
      <div v-if="propertiesFile" class="flex flex-col gap-[12px]">
        <div class="property-row">
          <span class="property-label">名称</span>
          <span class="property-value">{{ propertiesFile.filename }}</span>
        </div>
        <div class="property-row">
          <span class="property-label">类型</span>
          <span class="property-value">{{ propertiesFile.isDirectory ? '目录' : '文件' }}</span>
        </div>
        <div class="property-row">
          <span class="property-label">路径</span>
          <span class="property-value break-all">{{ propertiesPath }}</span>
        </div>
        <div class="property-row items-start">
          <span class="property-label pt-[5px]">大小</span>
          <div class="flex min-w-0 flex-1 flex-wrap items-center gap-[8px]">
            <span class="property-value flex-none">{{ propertiesSizeText }}</span>
            <NButton
              v-if="propertiesFile.isDirectory"
              quaternary
              round
              size="small"
              :loading="calculatingDirectorySize"
              @click="calculateDirectorySize"
            >
              {{ calculatedDirectorySize === null ? '计算目录大小' : '重新计算' }}
            </NButton>
          </div>
        </div>
        <div class="property-row">
          <span class="property-label">权限</span>
          <div class="flex min-w-0 flex-1 flex-wrap items-center gap-[8px]">
            <span class="property-value flex-none font-mono">{{ propertiesPermission }}</span>
            <NButton
              quaternary
              round
              size="small"
              @click="openPermissionDialog(propertiesFile, propertiesPath)"
              >修改</NButton
            >
          </div>
        </div>
        <div class="property-row">
          <span class="property-label">修改时间</span>
          <span class="property-value">{{ formatModifyTime(propertiesFile.modifyTime) }}</span>
        </div>
        <div class="property-row items-start">
          <span class="property-label pt-[2px]">原始信息</span>
          <span class="property-value break-all font-mono text-[12px]">{{
            propertiesFile.longname || '-'
          }}</span>
        </div>
      </div>
    </NModal>

    <NModal
      v-model:show="showPermissionDialog"
      preset="card"
      title="修改权限"
      style="width: min(560px, calc(100vw - 24px))"
    >
      <div v-if="permissionFile" class="flex flex-col gap-[14px]">
        <div class="flex flex-col gap-[8px]">
          <div class="property-row">
            <span class="property-label">名称</span>
            <span class="property-value">{{ permissionFile.filename }}</span>
          </div>
          <div class="property-row">
            <span class="property-label">路径</span>
            <span class="property-value break-all">{{ permissionItemPath }}</span>
          </div>
          <div class="property-row">
            <span class="property-label">当前权限</span>
            <span class="property-value font-mono">{{ permissionCurrentText }}</span>
          </div>
        </div>

        <NAlert v-if="!isPermissionParsed" type="warning" :bordered="false">
          无法解析当前权限，请手动选择要应用的权限。
        </NAlert>
        <NAlert v-else-if="hasSpecialPermissionBits" type="warning" :bordered="false">
          当前包含特殊权限位，应用后将只设置读取、写入和执行权限。
        </NAlert>

        <div class="flex flex-col gap-[10px]">
          <div
            class="grid grid-cols-[88px_repeat(3,minmax(0,1fr))] items-center gap-[8px] text-[13px]"
          >
            <span />
            <span
              v-for="action in permissionActions"
              :key="action.key"
              class="text-center font-600"
            >
              {{ action.label }}
            </span>
            <template v-for="subject in permissionSubjects" :key="subject.key">
              <span class="font-600">{{ subject.label }}</span>
              <NCheckbox
                v-for="action in permissionActions"
                :key="`${subject.key}-${action.key}`"
                class="justify-center"
                :checked="permissionMatrix[subject.key][action.key]"
                @update:checked="
                  (checked: boolean) => setPermissionChecked(subject.key, action.key, checked)
                "
              />
            </template>
          </div>
        </div>

        <div class="flex flex-wrap gap-[8px]">
          <NButton
            v-for="preset in permissionPresets"
            :key="preset.mode"
            quaternary
            round
            size="small"
            @click="applyPermissionMode(preset.mode)"
          >
            {{ preset.label }}
          </NButton>
        </div>

        <NAlert v-if="permissionFile.isDirectory" type="info" :bordered="false">
          <div class="flex flex-col gap-[8px]">
            <NCheckbox v-model:checked="permissionRecursive">
              递归应用到目录内所有文件和子目录
            </NCheckbox>
            <span v-if="permissionRecursive">
              递归修改会影响该目录下全部项目，请确认权限策略后再应用。
            </span>
          </div>
        </NAlert>

        <div
          class="rounded-[12px] px-[12px] py-[10px] text-[13px]"
          :class="
            settingsStore.isDark
              ? 'bg-[rgba(15,23,42,0.54)] text-[rgba(226,232,240,0.96)]'
              : 'bg-[rgba(241,245,249,0.92)] text-[rgba(51,65,85,0.96)]'
          "
        >
          将应用权限：<span class="font-mono font-700">{{ permissionMode }}</span>
        </div>

        <NSpace justify="end">
          <NButton
            quaternary
            round
            :disabled="changingPermission"
            @click="showPermissionDialog = false"
            >取消</NButton
          >
          <NButton
            quaternary
            round
            type="primary"
            :loading="changingPermission"
            @click="confirmPermissionChange"
            >应用权限</NButton
          >
        </NSpace>
      </div>
    </NModal>

    <NModal
      v-model:show="showDeleteDialog"
      preset="dialog"
      title="确认删除"
      positive-text="删除"
      negative-text="取消"
      :positive-button-props="{ loading: deletingFiles }"
      @positive-click="confirmDelete"
      @negative-click="showDeleteDialog = false"
    >
      删除
      {{
        selectedFiles.length > 1
          ? `这 ${selectedFiles.length} 个项目`
          : '`' + (selectedFile?.filename ?? '') + '`'
      }}
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

.favorite-popover-scrollbar {
  --favorite-scrollbar-thumb: rgba(148, 163, 184, 0.28);
  --favorite-scrollbar-thumb-hover: rgba(96, 165, 250, 0.56);
  --favorite-scrollbar-rail: rgba(148, 163, 184, 0.08);
}

.favorite-popover-scrollbar-light {
  --favorite-scrollbar-thumb: rgba(100, 116, 139, 0.2);
  --favorite-scrollbar-thumb-hover: rgba(37, 99, 235, 0.42);
  --favorite-scrollbar-rail: rgba(100, 116, 139, 0.08);
}

.favorite-popover-scrollbar :deep(.n-scrollbar-rail) {
  right: 1px;
  width: 6px;
  border-radius: 999px;
  background: var(--favorite-scrollbar-rail);
}

.favorite-popover-scrollbar :deep(.n-scrollbar-rail__scrollbar) {
  width: 6px;
  border-radius: 999px;
  background-color: var(--favorite-scrollbar-thumb) !important;
  transition:
    background-color 0.18s ease,
    opacity 0.18s ease;
}

.favorite-popover-scrollbar:hover :deep(.n-scrollbar-rail__scrollbar),
.favorite-popover-scrollbar :deep(.n-scrollbar-rail__scrollbar:hover) {
  background-color: var(--favorite-scrollbar-thumb-hover) !important;
}
</style>
