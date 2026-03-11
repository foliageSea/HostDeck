import { defineStore } from 'pinia'
import { ref } from 'vue'
import { useSshStore } from './ssh'
import { useToastStore } from './toast'
import { resolve, dirname } from '../utils/path'

export interface FileItem {
  filename: string
  longname: string
  isDirectory: boolean
  size: number
  modifyTime?: string
}

export type ViewMode = 'list' | 'grid'

export const useFileStore = defineStore('file', () => {
  const sshStore = useSshStore()
  const toast = useToastStore()

  const currentPath = ref('/')
  const files = ref<FileItem[]>([])
  const viewMode = ref<ViewMode>('list')
  const selectedFiles = ref<Set<string>>(new Set())
  const loading = ref(false)

  // Clipboard for copy/move operations
  // structure: { action: 'copy' | 'move', paths: string[], sourcePath: string }
  const clipboard = ref<{ action: 'copy' | 'move', paths: string[], sourcePath: string } | null>(null)

  const fetchFiles = async (path?: string) => {
    if (!sshStore.sessionId) return

    // Calculate target path
    let targetPath = currentPath.value
    if (path !== undefined) {
      // Resolve new path relative to current path if not absolute
      // This handles '..', '.', and normalizes the path
      targetPath = resolve(currentPath.value, path)
    }

    loading.value = true
    try {
      const res = await fetch(`/api/files/list?sessionId=${sshStore.sessionId}&path=${encodeURIComponent(targetPath)}`)
      if (!res.ok) throw new Error('Failed to fetch files')

      const data = await res.json()
      // sort: folders first, then files
      files.value = data.sort((a: FileItem, b: FileItem) => {
        if (a.isDirectory === b.isDirectory) {
          return a.filename.localeCompare(b.filename)
        }
        return a.isDirectory ? -1 : 1
      })
      selectedFiles.value.clear()

      // Only update currentPath if request succeeds
      currentPath.value = targetPath
    } catch (e: any) {
      toast.error(`Failed to list files: ${e.message}`)
    } finally {
      loading.value = false
    }
  }

  const navigate = (filename: string) => {
    fetchFiles(filename)
  }

  const navigateUp = () => {
    const parent = dirname(currentPath.value)
    if (parent !== currentPath.value) {
      fetchFiles(parent)
    }
  }

  const refresh = () => fetchFiles()

  const toggleSelection = (filename: string, multi: boolean) => {
    if (multi) {
      if (selectedFiles.value.has(filename)) {
        selectedFiles.value.delete(filename)
      } else {
        selectedFiles.value.add(filename)
      }
    } else {
      selectedFiles.value.clear()
      selectedFiles.value.add(filename)
    }
  }

  const clearSelection = () => selectedFiles.value.clear()

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

  return {
    currentPath,
    files,
    viewMode,
    selectedFiles,
    loading,
    clipboard,
    fetchFiles,
    navigate,
    navigateUp,
    refresh,
    toggleSelection,
    clearSelection,
    selectAll,
    copySelection,
    cutSelection
  }
})
