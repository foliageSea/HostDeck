import { computed, reactive, ref } from 'vue'
import { useLocalStorage } from '@vueuse/core'
import { filesApi, type FileItem } from '@/api/files'
import { useSshStore } from '@/stores/ssh'
import { dirname, resolve } from '@/utils/path'

export type FileViewMode = 'grid' | 'list'

type FavoritePathsByConnection = Record<string, string[]>

function compareFiles(left: FileItem, right: FileItem) {
  if (left.isDirectory !== right.isDirectory) {
    return left.isDirectory ? -1 : 1
  }

  return left.filename.localeCompare(right.filename)
}

export function createFileStore() {
  const sshStore = useSshStore()

  const currentPath = ref('/')
  const files = ref<FileItem[]>([])
  const sessionId = ref<string | null>(null)
  const loading = ref(false)
  const viewMode = useLocalStorage<FileViewMode>('ssh-tool:files:view-mode', 'list')
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
      .sort(compareFiles)
  })

  const selectedFile = computed(() => {
    const currentSelectedName = selectedNames.value[0]
    if (!currentSelectedName) {
      return null
    }

    return files.value.find((file) => file.filename === currentSelectedName) ?? null
  })

  const hasSelection = computed(() => selectedNames.value.length > 0)

  const favoritePaths = computed(() => favoritePathsByConnection.value[getFavoriteConnectionKey()] ?? [])

  function getFavoriteConnectionKey() {
    return sshStore.connectionId ?? 'default'
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

  async function initSession() {
    if (sessionId.value || !sshStore.connectionId) {
      return
    }

    const response = await filesApi.createSession(sshStore.connectionId)
    sessionId.value = response.sessionId
  }

  async function fetchFiles(nextPath?: string) {
    loading.value = true

    try {
      await initSession()
      if (!sessionId.value) {
        return
      }

      const targetPath = nextPath ? resolve(currentPath.value, nextPath) : currentPath.value
      const response = await filesApi.list(sessionId.value, targetPath)
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

  return reactive({
    backHistory,
    clearSelection,
    currentPath,
    displayFiles,
    fetchFiles,
    favoritePaths,
    files,
    forwardHistory,
    hasSelection,
    initSession,
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
    sessionId,
    toggleFavoritePath,
    viewMode,
  })
}
