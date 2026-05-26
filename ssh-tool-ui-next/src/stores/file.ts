import { computed, reactive, ref, watch } from 'vue'
import { useLocalStorage } from '@vueuse/core'
import { filesApi, type FileItem } from '@/api/files'
import { dirname, resolve } from '@/utils/path'

export type FileViewMode = 'grid' | 'list'
export type FileSortKey = 'name' | 'size' | 'modifyTime'
export type FileSortDirection = 'asc' | 'desc'

interface FileSortState {
  direction: FileSortDirection
  key: FileSortKey
}

type FavoritePathsByConnection = Record<string, string[]>

interface FileStoreConnection {
  connectionId: string | null
  host: string
  port: number | null
  username: string
}

function compareFileValue(left: FileItem, right: FileItem, key: FileSortKey) {
  if (key === 'size') {
    return left.size - right.size
  }

  if (key === 'modifyTime') {
    const leftTime = left.modifyTime ? new Date(left.modifyTime).getTime() : Number.NaN
    const rightTime = right.modifyTime ? new Date(right.modifyTime).getTime() : Number.NaN

    if (Number.isNaN(leftTime) && Number.isNaN(rightTime)) {
      return 0
    }

    if (Number.isNaN(leftTime)) {
      return 1
    }

    if (Number.isNaN(rightTime)) {
      return -1
    }

    return leftTime - rightTime
  }

  return left.filename.localeCompare(right.filename)
}

function compareFiles(left: FileItem, right: FileItem, sortState: FileSortState) {
  if (left.isDirectory !== right.isDirectory) {
    return left.isDirectory ? -1 : 1
  }

  const result = compareFileValue(left, right, sortState.key)
  if (result !== 0) {
    return sortState.direction === 'asc' ? result : -result
  }

  return left.filename.localeCompare(right.filename)
}

export function createFileStore(connection: FileStoreConnection) {
  const currentPath = ref('/')
  const files = ref<FileItem[]>([])
  const currentConnectionId = computed(() => connection.connectionId)
  const loading = ref(false)
  const viewMode = useLocalStorage<FileViewMode>('ssh-tool:files:view-mode', 'grid')
  const sortState = useLocalStorage<FileSortState>('ssh-tool:files:sort', { direction: 'asc', key: 'name' })
  const favoritePathsByConnection = useLocalStorage<FavoritePathsByConnection>('ssh-tool:files:favorite-paths', {})
  const selectedNames = ref<string[]>([])
  const lastSelectedName = ref<string | null>(null)
  const search = ref('')
  const backHistory = ref<string[]>([])
  const forwardHistory = ref<string[]>([])

  const displayFiles = computed(() => {
    const keyword = search.value.trim().toLowerCase()
    return [...files.value]
      .filter((file) => file.filename !== '.' && file.filename !== '..')
      .filter((file) => !keyword || file.filename.toLowerCase().includes(keyword))
      .sort((left, right) => compareFiles(left, right, sortState.value))
  })

  const selectedFile = computed(() => {
    const currentSelectedName = selectedNames.value[0]
    if (!currentSelectedName) {
      return null
    }

    return files.value.find((file) => file.filename === currentSelectedName) ?? null
  })

  const hasSelection = computed(() => selectedNames.value.length > 0)

  const favoriteConnectionKey = computed(() => getFavoriteConnectionKey())
  const favoritePaths = computed(() => favoritePathsByConnection.value[favoriteConnectionKey.value] ?? [])

  watch(favoriteConnectionKey, migrateLegacyFavoritePaths, { immediate: true })

  function getFavoriteConnectionKey() {
    return getStableFavoriteConnectionKey() ?? getLegacyFavoriteConnectionKey()
  }

  function getStableFavoriteConnectionKey() {
    const host = connection.host.trim()
    const username = connection.username.trim()
    const port = connection.port

    if (!host || !username || port === null) {
      return null
    }

    return `${username}@${host}:${port}`
  }

  function getLegacyFavoriteConnectionKey() {
    return connection.connectionId ?? 'default'
  }

  function migrateLegacyFavoritePaths() {
    const stableKey = getStableFavoriteConnectionKey()
    const legacyKey = connection.connectionId

    if (!stableKey || !legacyKey || stableKey === legacyKey) {
      return
    }

    const storedPaths = favoritePathsByConnection.value
    if (storedPaths[stableKey]?.length || !storedPaths[legacyKey]?.length) {
      return
    }

    favoritePathsByConnection.value = {
      ...storedPaths,
      [stableKey]: storedPaths[legacyKey],
    }
  }

  function normalizeFavoritePath(path: string) {
    return resolve(currentPath.value, path)
  }

  function setFavoritePaths(paths: string[]) {
    favoritePathsByConnection.value = {
      ...favoritePathsByConnection.value,
      [getFavoriteConnectionKey()]: paths,
    }
  }

  function isFavoritePath(path: string) {
    return favoritePaths.value.includes(normalizeFavoritePath(path))
  }

  function addFavoritePath(path: string) {
    const targetPath = normalizeFavoritePath(path)
    if (favoritePaths.value.includes(targetPath)) {
      return
    }

    setFavoritePaths([targetPath, ...favoritePaths.value])
  }

  function removeFavoritePath(path: string) {
    const targetPath = normalizeFavoritePath(path)
    setFavoritePaths(favoritePaths.value.filter((favoritePath) => favoritePath !== targetPath))
  }

  function toggleFavoritePath(path: string) {
    if (isFavoritePath(path)) {
      removeFavoritePath(path)
      return false
    }

    addFavoritePath(path)
    return true
  }

  async function fetchFiles(nextPath?: string) {
    loading.value = true

    try {
      const connectionId = currentConnectionId.value
      if (!connectionId) {
        return
      }

      const targetPath = nextPath ? resolve(currentPath.value, nextPath) : currentPath.value
      const response = await filesApi.list(connectionId, targetPath)
      files.value = response
      currentPath.value = targetPath

      selectedNames.value = selectedNames.value.filter((selectedName) => response.some((file) => file.filename === selectedName))
      if (selectedNames.value.length === 0) {
        lastSelectedName.value = null
      }
    } finally {
      loading.value = false
    }
  }

  async function navigateTo(path: string) {
    const targetPath = resolve(currentPath.value, path)
    if (targetPath === currentPath.value) {
      await fetchFiles(targetPath)
      return
    }

    const previousPath = currentPath.value
    await fetchFiles(targetPath)
    if (currentPath.value === targetPath) {
      backHistory.value = [...backHistory.value, previousPath]
      forwardHistory.value = []
    }
  }

  async function navigateUp() {
    const parentPath = dirname(currentPath.value)
    if (parentPath !== currentPath.value) {
      await navigateTo(parentPath)
    }
  }

  async function navigateBack() {
    const targetPath = backHistory.value[backHistory.value.length - 1]
    if (!targetPath) {
      return
    }

    const previousPath = currentPath.value
    await fetchFiles(targetPath)
    backHistory.value = backHistory.value.slice(0, -1)
    forwardHistory.value = [...forwardHistory.value, previousPath]
  }

  async function navigateForward() {
    const targetPath = forwardHistory.value[forwardHistory.value.length - 1]
    if (!targetPath) {
      return
    }

    const previousPath = currentPath.value
    await fetchFiles(targetPath)
    forwardHistory.value = forwardHistory.value.slice(0, -1)
    backHistory.value = [...backHistory.value, previousPath]
  }

  function selectFile(file: FileItem, options?: { append?: boolean; range?: boolean }) {
    if (options?.range && lastSelectedName.value) {
      const orderedFiles = displayFiles.value
      const startIndex = orderedFiles.findIndex((item) => item.filename === lastSelectedName.value)
      const endIndex = orderedFiles.findIndex((item) => item.filename === file.filename)

      if (startIndex !== -1 && endIndex !== -1) {
        const [from, to] = startIndex < endIndex ? [startIndex, endIndex] : [endIndex, startIndex]
        selectedNames.value = orderedFiles.slice(from, to + 1).map((item) => item.filename)
        return
      }
    }

    if (options?.append) {
      if (selectedNames.value.includes(file.filename)) {
        selectedNames.value = selectedNames.value.filter((name) => name !== file.filename)
      } else {
        selectedNames.value = [...selectedNames.value, file.filename]
      }
      lastSelectedName.value = file.filename
      return
    }

    selectedNames.value = [file.filename]
    lastSelectedName.value = file.filename
  }

  function clearSelection() {
    selectedNames.value = []
    lastSelectedName.value = null
  }

  function setSelectedNames(names: string[]) {
    const availableNames = new Set(displayFiles.value.map((file) => file.filename))
    selectedNames.value = names.filter((name) => availableNames.has(name))
    lastSelectedName.value = selectedNames.value[selectedNames.value.length - 1] ?? null
  }

  function selectAll() {
    selectedNames.value = displayFiles.value.map((file) => file.filename)
    lastSelectedName.value = selectedNames.value[selectedNames.value.length - 1] ?? null
  }

  function setSortKey(key: FileSortKey) {
    sortState.value = {
      direction: sortState.value.key === key ? sortState.value.direction : 'asc',
      key,
    }
  }

  function toggleSortDirection() {
    sortState.value = {
      ...sortState.value,
      direction: sortState.value.direction === 'asc' ? 'desc' : 'asc',
    }
  }

  return reactive({
    backHistory,
    clearSelection,
    connectionId: currentConnectionId,
    currentPath,
    displayFiles,
    fetchFiles,
    favoritePaths,
    files,
    forwardHistory,
    hasSelection,
    isFavoritePath,
    lastSelectedName,
    loading,
    navigateBack,
    navigateForward,
    navigateTo,
    navigateUp,
    removeFavoritePath,
    search,
    selectAll,
    selectFile,
    selectedFile,
    selectedNames,
    setSelectedNames,
    setSortKey,
    sortDirection: computed(() => sortState.value.direction),
    sortKey: computed(() => sortState.value.key),
    toggleFavoritePath,
    toggleSortDirection,
    viewMode,
  })
}
