import { ref } from 'vue'
import { toast } from 'vue-sonner'
import { resolve } from '@/utils/path'
import { fileApi } from '@/api/files'
import type { FileItem } from '@/stores/file'

/**
 * 封装文件系统的核心操作（增删改查、上传下载、打开等）
 */
export function useFileOperations(fileStore: any, desktopStore: any) {
  const showMkdirModal = ref(false)
  const showRenameModal = ref(false)
  const showDeleteModal = ref(false)
  const showCreateFileModal = ref(false)
  const showPropertiesModal = ref(false)
  const newItemName = ref('')

  /**
   * 获取完整路径
   */
  const getFullPath = (filename: string) => {
    return resolve(fileStore.currentPath, filename)
  }

  /**
   * 处理下载操作
   */
  const handleDownload = async () => {
    if (fileStore.selectedFiles.size === 0) return

    if (fileStore.selectedFiles.size === 1) {
      const filename = Array.from(fileStore.selectedFiles)[0] as string
      const file = fileStore.files.find((f: FileItem) => f.filename === filename)
      if (file && !file.isDirectory) {
        downloadFile(file)
        return
      }
    }

    // 批量下载
    try {
      fileStore.loading = true
      const paths = Array.from(fileStore.selectedFiles).map(filename => getFullPath(filename as string))

      const blob = await fileApi.batchDownload(fileStore.sessionId!, paths)

      const url = window.URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = 'download.tar.gz'
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      window.URL.revokeObjectURL(url)
    } catch (e: any) {
      toast.error(`Download failed: ${e.message}`)
    } finally {
      fileStore.loading = false
    }
  }

  /**
   * 下载单个文件
   */
  const downloadFile = async (file: FileItem) => {
    const path = getFullPath(file.filename)
    window.open(`/api/files/read?sessionId=${fileStore.sessionId}&path=${encodeURIComponent(path)}&download=true`, '_blank')
  }

  /**
   * 处理粘贴操作
   */
  const handlePaste = async () => {
    if (!fileStore.clipboard) return

    const { action, paths, sourcePath } = fileStore.clipboard
    // 如果是移动操作，检查源目录和目标目录是否相同
    if (action === 'move' && sourcePath === fileStore.currentPath) {
      toast.info('Source and destination are same')
      return
    }

    fileStore.loading = true
    try {
      for (const filename of paths) {
        const fullSourcePath = resolve(sourcePath, filename)
        const fullTargetPath = resolve(fileStore.currentPath, filename)

        if (action === 'copy') {
          await fileApi.copy(fileStore.sessionId!, fullSourcePath, fullTargetPath)
        } else {
          await fileApi.rename(fileStore.sessionId!, fullSourcePath, fullTargetPath)
        }
      }

      fileStore.notifyFileSystemChange()
      if (action === 'move') fileStore.clipboard = null
      toast.success(action === 'copy' ? 'Copied' : 'Moved')
    } catch (e: any) {
      toast.error(`Paste failed: ${e.message}`)
    } finally {
      fileStore.loading = false
    }
  }

  /**
   * 触发重命名弹窗
   */
  const openRenameModal = () => {
    const filename = Array.from(fileStore.selectedFiles)[0] as string
    if (!filename) return
    newItemName.value = filename
    showRenameModal.value = true
  }

  /**
   * 执行重命名
   */
  const handleRename = async () => {
    const oldName = Array.from(fileStore.selectedFiles)[0] as string
    if (!newItemName.value || !oldName) return
    const oldPath = getFullPath(oldName)
    const newPath = getFullPath(newItemName.value)

    try {
      await fileApi.rename(fileStore.sessionId!, oldPath, newPath)

      toast.success('Renamed')
      showRenameModal.value = false
      fileStore.notifyFileSystemChange()
    } catch (e: any) {
      toast.error(`Rename failed: ${e.message}`)
    }
  }

  /**
   * 触发新建文件夹弹窗
   */
  const openMkdirModal = () => {
    newItemName.value = ''
    showMkdirModal.value = true
  }

  const openCreateFileModal = () => {
    newItemName.value = ''
    showCreateFileModal.value = true
  }

  /**
   * 执行新建文件夹
   */
  const handleMkdir = async () => {
    if (!newItemName.value) return
    const path = getFullPath(newItemName.value)

    try {
      await fileApi.mkdir(fileStore.sessionId!, path)

      toast.success('Directory created')
      showMkdirModal.value = false
      fileStore.notifyFileSystemChange()
    } catch (e: any) {
      toast.error(`Mkdir failed: ${e.message}`)
    }
  }

  const handleCreateFile = async () => {
    const filename = newItemName.value.trim()
    if (!filename) return
    if (filename.includes('/')) {
      toast.error('File name cannot include path separators')
      return
    }

    const path = getFullPath(filename)

    try {
      await fileApi.writeFile(fileStore.sessionId!, path, '')
      fileStore.pendingSelectedFilename = filename
      toast.success('File created')
      showCreateFileModal.value = false
      fileStore.notifyFileSystemChange()
    } catch (e: any) {
      toast.error(`Create file failed: ${e.message}`)
    }
  }

  /**
   * 触发删除弹窗
   */
  const openDeleteModal = () => {
    if (fileStore.selectedFiles.size > 0) {
      showDeleteModal.value = true
    }
  }

  const openPropertiesModal = () => {
    if (fileStore.selectedFiles.size !== 1) return
    showPropertiesModal.value = true
  }

  /**
   * 执行删除
   */
  const handleDelete = async () => {
    try {
      fileStore.loading = true
      for (const filename of fileStore.selectedFiles) {
        const path = getFullPath(filename as string)
        await fileApi.deleteFile(fileStore.sessionId!, path)
      }
      toast.success('Deleted')
      showDeleteModal.value = false
      fileStore.notifyFileSystemChange()
    } catch (e: any) {
      toast.error(`Delete failed: ${e.message}`)
    } finally {
      fileStore.loading = false
    }
  }

  /**
   * 执行文件上传
   */
  const uploadFiles = async (files: FileList) => {
    if (!files || files.length === 0) return

    const fileArray = Array.from(files)
    const totalSize = fileArray.reduce((acc, file) => acc + file.size, 0)
    let uploadedSize = 0

    fileStore.uploadStatus = {
      uploading: true,
      total: fileArray.length,
      current: 0,
      currentFilename: '',
      success: 0,
      failed: 0,
      percent: 0
    }

    try {
      for (const file of fileArray) {
        fileStore.uploadStatus.currentFilename = file.name
        fileStore.uploadStatus.current++

        const formData = new FormData()
        formData.append('file', file)

        try {
          await fileApi.uploadFile(
            fileStore.sessionId!,
            fileStore.currentPath,
            formData,
            (loaded: number, _total: number) => {
              const currentFileProgress = loaded
              const totalProgress = uploadedSize + currentFileProgress
              fileStore.uploadStatus.percent = Math.min(100, Math.round((totalProgress / totalSize) * 100))
            }
          )

          fileStore.uploadStatus.success++
        } catch (e: any) {
          console.error(`Failed to upload ${file.name}`, e)
          fileStore.uploadStatus.failed++
          toast.error(`Failed to upload ${file.name}: ${e.message}`)
        } finally {
          uploadedSize += file.size
          fileStore.uploadStatus.percent = Math.min(100, Math.round((uploadedSize / totalSize) * 100))
        }
      }

      if (fileStore.uploadStatus.success > 0) {
        toast.success(`Uploaded ${fileStore.uploadStatus.success} files` + (fileStore.uploadStatus.failed > 0 ? `, ${fileStore.uploadStatus.failed} failed` : ''))
        fileStore.notifyFileSystemChange()
      }
    } catch (e: any) {
      toast.error(`Upload process failed: ${e.message}`)
    } finally {
      setTimeout(() => {
        fileStore.uploadStatus.uploading = false
      }, 1000)
    }
  }

  /**
   * 处理拖拽文件上传
   */
  const handleDrop = (e: DragEvent) => {
    if (e.dataTransfer?.files) {
      uploadFiles(e.dataTransfer.files)
    }
  }

  /**
   * 打开文件（根据类型判断调用编辑器或媒体查看器或下载）
   */
  const handleOpen = async (file: FileItem) => {
    if (file.isDirectory) {
      fileStore.navigate(file.filename)
    } else {
      const ext = file.filename.split('.').pop()?.toLowerCase()

      const imageExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'ico']
      const videoExts = ['mp4', 'webm', 'ogg', 'mov', 'mkv', 'avi']

      if (ext && fileStore.editableExtensions.includes(ext)) {
        openEditor(file)
      } else if (ext && (imageExts.includes(ext) || videoExts.includes(ext))) {
        openMediaViewer(file)
      } else {
        // downloadFile(file)
      }
    }
  }

  const openEditor = async (file: FileItem) => {
    desktopStore.openWindow('editor', {
      path: getFullPath(file.filename),
      sessionId: fileStore.sessionId,
      title: file.filename
    })
  }

  const openMediaViewer = async (file: FileItem) => {
    const imageExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'ico']
    const videoExts = ['mp4', 'webm', 'ogg', 'mov', 'mkv', 'avi']
    const mediaExts = [...imageExts, ...videoExts]

    const playlist = fileStore.files
      .filter((f: FileItem) => !f.isDirectory)
      .filter((f: FileItem) => {
        const ext = f.filename.split('.').pop()?.toLowerCase()
        return ext && mediaExts.includes(ext)
      })
      .map((f: FileItem) => ({
        path: getFullPath(f.filename),
        filename: f.filename,
        type: videoExts.includes(f.filename.split('.').pop()?.toLowerCase() || '') ? 'video' : 'image'
      }))

    desktopStore.openWindow('media-viewer', {
      path: getFullPath(file.filename),
      sessionId: fileStore.sessionId,
      title: file.filename,
      playlist
    })
  }

  const handleSelectAll = () => {
    fileStore.selectAll()
  }

  /**
   * 在终端中打开当前目录（新开终端窗口，并自动 cd 过去）
   */
  const openTerminalHere = () => {
    desktopStore.openWindow('terminal', {
      title: `终端: ${fileStore.currentPath}`,
      cwd: fileStore.currentPath,
    })
  }

  return {
    showMkdirModal,
    showRenameModal,
    showDeleteModal,
    showCreateFileModal,
    showPropertiesModal,
    newItemName,
    getFullPath,
    handleDownload,
    downloadFile,
    handlePaste,
    openRenameModal,
    handleRename,
    openMkdirModal,
    handleMkdir,
    openCreateFileModal,
    handleCreateFile,
    openDeleteModal,
    openPropertiesModal,
    handleDelete,
    uploadFiles,
    handleDrop,
    handleOpen,
    handleSelectAll,
    openTerminalHere
  }
}
