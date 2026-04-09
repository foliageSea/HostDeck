import { ref, inject, reactive, type InjectionKey, watch, computed } from 'vue'
import { useStorage } from '@vueuse/core'
import { useSshStore } from './ssh'
import { useToastStore } from './toast'
import { useSettingsStore } from './settings'
import { resolve, dirname } from '../utils/path'
import { fileApi } from '@/api/files'

export interface FileItem {
  filename: string
  longname: string
  isDirectory: boolean
  size: number
  modifyTime?: string
}

export type ViewMode = 'list' | 'grid'
export type SortBy = 'name' | 'size' | 'modifyTime' | 'type'
export type SortOrder = 'asc' | 'desc'
export type FilterType = 'all' | 'directory' | 'file'

export type FileStore = ReturnType<typeof createFileStore>

export const FileStoreKey: InjectionKey<FileStore> = Symbol('FileStore')

// Global state shared across all file manager instances
const globalClipboard = ref<{ action: 'copy' | 'move', paths: string[], sourcePath: string } | null>(null)
const refreshSignal = ref(0)

export function createFileStore() {
  const sshStore = useSshStore()
  const toast = useToastStore()
  const settingsStore = useSettingsStore()

  const currentPath = ref('/')
  const files = ref<FileItem[]>([])
  const viewMode = ref<ViewMode>('grid')
  const selectedFiles = ref<Set<string>>(new Set())
  const lastSelectedFilename = ref<string | null>(null)
  const pendingSelectedFilename = ref<string | null>(null)
  const loading = ref(false)
  const sessionId = ref<string | null>(null)
  const backHistory = ref<string[]>([])
  const forwardHistory = ref<string[]>([])
  const recentPaths = useStorage<string[]>('ssh-tool-file-recent-paths', [])
  const searchQuery = ref('')
  const sortBy = ref<SortBy>('name')
  const sortOrder = ref<SortOrder>('asc')
  const filterType = ref<FilterType>('all')

  // Upload state
  const uploadStatus = ref<{
    uploading: boolean,
    total: number,
    current: number,
    currentFilename: string,
    success: number,
    failed: number,
    percent: number
  }>({
    uploading: false,
    total: 0,
    current: 0,
    currentFilename: '',
    success: 0,
    failed: 0,
    percent: 0
  })

  // Clipboard for copy/move operations (shared global state)
  const clipboard = globalClipboard

  // Watch for global refresh signal
  watch(refreshSignal, () => {
    if (sessionId.value) {
      fetchFiles()
    }
  })

  const notifyFileSystemChange = () => {
    refreshSignal.value++
  }

  // Favorites
  const favorites = useStorage<string[]>('ssh-tool-file-favorites', [])

  const toggleFavorite = (path: string) => {
    const index = favorites.value.indexOf(path)
    if (index > -1) {
      favorites.value.splice(index, 1)
    } else {
      favorites.value.push(path)
    }
  }

  const isFavorite = (path: string) => {
    return favorites.value.includes(path)
  }

  // Configurable editable file extensions
  const editableExtensions = computed(() => {
    return Object.keys(settingsStore.languageMap)
  })

  const initSession = async () => {
    if (!sshStore.connectionId) return
    if (sessionId.value) return

    try {
      const data = await fileApi.createSession(sshStore.connectionId)
      sessionId.value = data.sessionId
    } catch (e: any) {
      console.error('Failed to init file session', e)
      toast.error(`Failed to init file session: ${e.message}`)
    }
  }

  const updateRecentPaths = (path: string) => {
    recentPaths.value = [path, ...recentPaths.value.filter(item => item !== path)].slice(0, 10)
  }

  const compareFiles = (a: FileItem, b: FileItem) => {
    if (a.isDirectory !== b.isDirectory) {
      return a.isDirectory ? -1 : 1
    }

    let result = 0
    switch (sortBy.value) {
      case 'size':
        result = (a.size || 0) - (b.size || 0)
        break
      case 'modifyTime':
        result = new Date(a.modifyTime || 0).getTime() - new Date(b.modifyTime || 0).getTime()
        break
      case 'type': {
        const aType = a.isDirectory ? '' : (a.filename.split('.').pop() || '').toLowerCase()
        const bType = b.isDirectory ? '' : (b.filename.split('.').pop() || '').toLowerCase()
        result = aType.localeCompare(bType) || a.filename.localeCompare(b.filename)
        break
      }
      case 'name':
      default:
        result = a.filename.localeCompare(b.filename)
        break
    }

    return sortOrder.value === 'asc' ? result : -result
  }

  const displayFiles = computed(() => {
    const normalizedQuery = searchQuery.value.trim().toLowerCase()

    return [...files.value]
      .filter((file) => file.filename !== '.' && file.filename !== '..')
      .filter((file) => {
        if (filterType.value === 'directory') return file.isDirectory
        if (filterType.value === 'file') return !file.isDirectory
        return true
      })
      .filter((file) => {
        if (!normalizedQuery) return true
        return file.filename.toLowerCase().includes(normalizedQuery)
      })
      .sort(compareFiles)
  })

  const fetchFiles = async (path?: string) => {
    if (!sessionId.value) {
      await initSession()
    }
    if (!sessionId.value) return

    // Calculate target path
    let targetPath = currentPath.value
    if (path !== undefined) {
      // Resolve new path relative to current path if not absolute
      // This handles '..', '.', and normalizes the path
      targetPath = resolve(currentPath.value, path)
    }

    loading.value = true
    try {
      const data = await fileApi.listFiles(sessionId.value, targetPath)

      files.value = data
      selectedFiles.value.clear()
      lastSelectedFilename.value = null

      if (pendingSelectedFilename.value) {
        const target = data.find((file) => file.filename === pendingSelectedFilename.value)
        if (target) {
          selectedFiles.value = new Set([target.filename])
          lastSelectedFilename.value = target.filename
        }
        pendingSelectedFilename.value = null
      }

      // Only update currentPath if request succeeds
      currentPath.value = targetPath
      updateRecentPaths(targetPath)
    } catch (e: any) {
      toast.error(`Failed to list files: ${e.message}`)
    } finally {
      loading.value = false
    }
  }

  const navigateTo = async (path: string, options?: { preserveHistory?: boolean }) => {
    const targetPath = resolve(currentPath.value, path)
    const shouldPreserveHistory = options?.preserveHistory !== false

    if (targetPath === currentPath.value) {
      await fetchFiles(targetPath)
      return
    }

    const previousPath = currentPath.value
    await fetchFiles(targetPath)

    if (currentPath.value === targetPath && shouldPreserveHistory && previousPath !== targetPath) {
      backHistory.value = [...backHistory.value, previousPath]
      forwardHistory.value = []
    }
  }

  const navigate = (filename: string) => {
    navigateTo(filename)
  }

  const navigateUp = async () => {
    const parent = dirname(currentPath.value)
    if (parent !== currentPath.value) {
      await navigateTo(parent)
    }
  }

  const navigateBack = async () => {
    const targetPath = backHistory.value[backHistory.value.length - 1]
    if (!targetPath) return

    const previousPath = currentPath.value
    await fetchFiles(targetPath)

    if (currentPath.value === targetPath) {
      backHistory.value = backHistory.value.slice(0, -1)
      forwardHistory.value = [...forwardHistory.value, previousPath]
    }
  }

  const navigateForward = async () => {
    const targetPath = forwardHistory.value[forwardHistory.value.length - 1]
    if (!targetPath) return

    const previousPath = currentPath.value
    await fetchFiles(targetPath)

    if (currentPath.value === targetPath) {
      forwardHistory.value = forwardHistory.value.slice(0, -1)
      backHistory.value = [...backHistory.value, previousPath]
    }
  }

  const refresh = () => fetchFiles()

  const selectSingle = (filename: string) => {
    selectedFiles.value = new Set([filename])
    lastSelectedFilename.value = filename
  }

  const toggleSelection = (filename: string, multi: boolean) => {
    if (multi) {
      if (selectedFiles.value.has(filename)) {
        selectedFiles.value.delete(filename)
      } else {
        selectedFiles.value.add(filename)
      }
      lastSelectedFilename.value = filename
    } else {
      selectSingle(filename)
    }
  }

  const selectRange = (filename: string, orderedFiles: FileItem[]) => {
    const anchor = lastSelectedFilename.value
    if (!anchor) {
      selectSingle(filename)
      return
    }

    const startIndex = orderedFiles.findIndex(file => file.filename === anchor)
    const endIndex = orderedFiles.findIndex(file => file.filename === filename)

    if (startIndex === -1 || endIndex === -1) {
      selectSingle(filename)
      return
    }

    const [from, to] = startIndex < endIndex ? [startIndex, endIndex] : [endIndex, startIndex]
    selectedFiles.value = new Set(orderedFiles.slice(from, to + 1).map(file => file.filename))
  }

  const clearSelection = () => {
    selectedFiles.value.clear()
    lastSelectedFilename.value = null
  }

  const selectAll = () => {
    files.value.forEach(f => selectedFiles.value.add(f.filename))
  }

  const copySelection = () => {
    if (selectedFiles.value.size === 0) return
    clipboard.value = {
      action: 'copy',
      paths: Array.from(selectedFiles.value),
      sourcePath: currentPath.value
    }
    toast.info(`Copied ${selectedFiles.value.size} items to clipboard`)
  }

  const cutSelection = () => {
    if (selectedFiles.value.size === 0) return
    clipboard.value = {
      action: 'move',
      paths: Array.from(selectedFiles.value),
      sourcePath: currentPath.value
    }
    toast.info(`Cut ${selectedFiles.value.size} items to clipboard`)
  }

  return reactive({
    currentPath,
    files,
    viewMode,
    selectedFiles,
    lastSelectedFilename,
    pendingSelectedFilename,
    loading,
    sessionId,
    backHistory,
    forwardHistory,
    recentPaths,
    searchQuery,
    sortBy,
    sortOrder,
    filterType,
    displayFiles,
    uploadStatus,
    clipboard,
    editableExtensions,
    initSession,
    fetchFiles,
    navigateTo,
    navigate,
    navigateUp,
    navigateBack,
    navigateForward,
    refresh,
    notifyFileSystemChange,
    selectSingle,
    toggleSelection,
    selectRange,
    clearSelection,
    selectAll,
    copySelection,
    cutSelection,
    favorites,
    toggleFavorite,
    isFavorite
  })
}

export function useFileStore() {
  const store = inject(FileStoreKey)
  if (!store) {
    throw new Error('useFileStore must be used within a component that provides it via createFileStore')
  }
  return store
}
