<template>
  <div class="h-full flex bg-background" @click="closeContextMenu">


    <!-- Main Content -->
    <div class="flex-1 flex flex-col min-w-0 bg-background">
      <FileToolbar :currentPath="fileStore.currentPath" :viewMode="fileStore.viewMode" @navigate="fileStore.navigate"
        @navigateUp="fileStore.navigateUp" @refresh="fileStore.refresh" @upload-files="uploadFiles"
        @mkdir="openMkdirModal" @toggleView="v => fileStore.viewMode = v" />

      <div class="flex-1 overflow-hidden relative select-none" @dragover.prevent @drop.prevent="handleDrop"
        @contextmenu.prevent="handleContainerContextMenu" @mousedown="handleMouseDown" ref="containerRef">

        <!-- Selection Box -->
        <div v-if="selectionBox.visible" class="absolute border border-primary bg-primary/20 z-50 pointer-events-none"
          :style="{
            left: selectionBox.x + 'px',
            top: selectionBox.y + 'px',
            width: selectionBox.width + 'px',
            height: selectionBox.height + 'px'
          }">
        </div>

        <FileList v-if="fileStore.viewMode === 'list'" :files="fileStore.files" :selectedFiles="fileStore.selectedFiles"
          @select="fileStore.toggleSelection" @selectAll="handleSelectAll" @open="handleOpen"
          @contextmenu="handleContextMenu" />
        <FileGrid v-else :files="fileStore.files" :selectedFiles="fileStore.selectedFiles"
          @select="fileStore.toggleSelection" @open="handleOpen" @contextmenu="handleContextMenu" />

        <Loading :loading="fileStore.loading" />
        <FileUploadProgress />
      </div>
    </div>

    <!-- Context Menu -->
    <FileContextMenu :visible="contextMenu.visible" :x="contextMenu.x" :y="contextMenu.y" :items="contextMenuItems"
      @close="closeContextMenu" />

    <!-- Modals -->
    <Modal :show="showMkdirModal" title="新建文件夹" @close="showMkdirModal = false" @confirm="handleMkdir">
      <Input v-model="newItemName" placeholder="文件夹名称" @keyup.enter="handleMkdir" ref="mkdirInput" />
    </Modal>

    <Modal :show="showRenameModal" title="重命名" @close="showRenameModal = false" @confirm="handleRename">
      <Input v-model="newItemName" placeholder="新名称" @keyup.enter="handleRename" ref="renameInput" />
    </Modal>

    <Modal :show="showDeleteModal" title="确认删除" @close="showDeleteModal = false" @confirm="handleDelete">
      <p class="text-muted-foreground">确定要删除选中的 {{ fileStore.selectedFiles.size }} 个项目吗？此操作无法撤销。</p>
    </Modal>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, nextTick, provide, reactive } from 'vue'
import { useEventListener } from '@vueuse/core'
import { createFileStore, FileStoreKey, type FileItem } from '../stores/file'
import { useSshStore } from '../stores/ssh'
import { toast } from 'vue-sonner'
import { useDesktopStore } from '../stores/desktop'
import { resolve } from '../utils/path'
import FileToolbar from '../components/file/FileToolbar.vue'
import FileList from '../components/file/FileList.vue'
import FileGrid from '../components/file/FileGrid.vue'
import FileContextMenu, { type MenuItem } from '../components/file/FileContextMenu.vue'
import FileUploadProgress from '../components/file/FileUploadProgress.vue'
import Modal from '../components/ui/Modal.vue'
import Loading from '../components/ui/Loading.vue'
import { Input } from '@/components/ui/input'
import {
  FolderIcon, FolderPlusIcon, DownloadIcon,
  CopyIcon, ScissorsIcon, ClipboardPasteIcon,
  EditIcon, Trash2Icon, TypeIcon, RefreshCwIcon,
  ClipboardIcon, StarIcon
} from 'lucide-vue-next'
import { fileApi } from '@/api/files'

const fileStore = createFileStore()
provide(FileStoreKey, fileStore)
const sshStore = useSshStore()
const desktopStore = useDesktopStore()

// Selection State
const containerRef = ref<HTMLElement | null>(null)
const isSelecting = ref(false)
const selectionBox = reactive({
  visible: false,
  x: 0,
  y: 0,
  width: 0,
  height: 0,
  startX: 0,
  startY: 0,
  startClientX: 0,
  startClientY: 0
})
let fileRects: { filename: string, rect: DOMRect }[] = []
let initialSelection = new Set<string>()

// State
const contextMenu = ref({ visible: false, x: 0, y: 0, file: null as FileItem | null })
const showMkdirModal = ref(false)
const showRenameModal = ref(false)
const showDeleteModal = ref(false)
const newItemName = ref('')
const mkdirInput = ref<any>()
const renameInput = ref<any>()

// Initial load
onMounted(async () => {
  if (sshStore.isConnected) {
    await fileStore.initSession()
    fileStore.fetchFiles()
  }
})

// Methods
const handleMouseDown = (e: MouseEvent) => {
  // Only handle left click
  if (e.button !== 0) return

  // Ignore if clicked on a file or scrollbar (if possible to detect)
  // Check if target is inside a file item
  if ((e.target as Element).closest('[data-filename]')) return

  // Start selection
  isSelecting.value = true
  const container = containerRef.value
  if (!container) return

  const rect = container.getBoundingClientRect()
  selectionBox.startX = e.clientX - rect.left
  selectionBox.startY = e.clientY - rect.top
  selectionBox.startClientX = e.clientX
  selectionBox.startClientY = e.clientY

  selectionBox.x = selectionBox.startX
  selectionBox.y = selectionBox.startY
  selectionBox.width = 0
  selectionBox.height = 0
  selectionBox.visible = true

  // Cache file rects
  const elements = container.querySelectorAll('[data-filename]')
  fileRects = Array.from(elements).map(el => ({
    filename: el.getAttribute('data-filename') || '',
    rect: el.getBoundingClientRect()
  }))

  // Handle modifiers
  if (e.ctrlKey || e.metaKey) {
    initialSelection = new Set(fileStore.selectedFiles)
  } else {
    initialSelection = new Set()
    fileStore.clearSelection()
  }
}

const handleMouseMove = (e: MouseEvent) => {
  if (!isSelecting.value) return
  if (!containerRef.value) return

  const containerRect = containerRef.value.getBoundingClientRect()

  // Update box position relative to container
  // Clamp to container bounds
  const currentX = Math.max(0, Math.min(e.clientX - containerRect.left, containerRect.width))
  const currentY = Math.max(0, Math.min(e.clientY - containerRect.top, containerRect.height))

  const x = Math.min(selectionBox.startX, currentX)
  const y = Math.min(selectionBox.startY, currentY)
  const width = Math.abs(currentX - selectionBox.startX)
  const height = Math.abs(currentY - selectionBox.startY)

  selectionBox.x = x
  selectionBox.y = y
  selectionBox.width = width
  selectionBox.height = height

  // Calculate intersection in client coordinates
  // Use the actual box coordinates relative to viewport for intersection check
  const boxLeft = containerRect.left + x
  const boxTop = containerRect.top + y
  const boxRight = boxLeft + width
  const boxBottom = boxTop + height

  const newSelection = new Set(initialSelection)

  fileRects.forEach(({ filename, rect }) => {
    // Check intersection
    const isIntersecting = !(
      rect.right < boxLeft ||
      rect.left > boxRight ||
      rect.bottom < boxTop ||
      rect.top > boxBottom
    )

    if (isIntersecting) {
      newSelection.add(filename)
    }
  })

  // Update store
  fileStore.selectedFiles = newSelection
}

const handleMouseUp = () => {
  if (!isSelecting.value) return
  isSelecting.value = false
  selectionBox.visible = false
  fileRects = []
  initialSelection.clear()
}

useEventListener(window, 'mousemove', handleMouseMove)
useEventListener(window, 'mouseup', handleMouseUp)

const getFullPath = (filename: string) => {
  return resolve(fileStore.currentPath, filename)
}

const handleDownload = async () => {
  if (fileStore.selectedFiles.size === 0) return

  if (fileStore.selectedFiles.size === 1) {
    const filename = Array.from(fileStore.selectedFiles)[0]
    const file = fileStore.files.find(f => f.filename === filename)
    if (file && !file.isDirectory) {
      downloadFile(file)
      return
    }
  }

  // Batch download
  try {
    fileStore.loading = true
    const paths = Array.from(fileStore.selectedFiles).map(filename => getFullPath(filename))

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

const handlePaste = async () => {
  if (!fileStore.clipboard) return

  const { action, paths, sourcePath } = fileStore.clipboard
  // If moving, check if source and target are same
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

const openRenameModal = () => {
  const filename = Array.from(fileStore.selectedFiles)[0]
  if (!filename) return
  newItemName.value = filename
  showRenameModal.value = true
  nextTick(() => renameInput.value?.$el?.focus())
}

const handleRename = async () => {
  const oldName = Array.from(fileStore.selectedFiles)[0]
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

const openMkdirModal = () => {
  newItemName.value = ''
  showMkdirModal.value = true
  nextTick(() => mkdirInput.value?.$el?.focus())
}

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

const handleDelete = async () => {
  try {
    fileStore.loading = true
    for (const filename of fileStore.selectedFiles) {
      const path = getFullPath(filename)
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
          (loaded, _total) => {
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
        // Update progress after each file (success or fail)
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
    // Delay hiding the progress bar slightly to show 100%
    setTimeout(() => {
      fileStore.uploadStatus.uploading = false
    }, 1000)
  }
}

const handleSelectAll = () => {
  fileStore.selectAll()
}

const handleOpen = async (file: FileItem) => {
  if (file.isDirectory) {
    fileStore.navigate(file.filename)
  } else {
    // Check file extension
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
    .filter(f => !f.isDirectory)
    .filter(f => {
      const ext = f.filename.split('.').pop()?.toLowerCase()
      return ext && mediaExts.includes(ext)
    })
    .map(f => ({
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

const downloadFile = async (file: FileItem) => {
  const path = getFullPath(file.filename)
  window.open(`/api/files/read?sessionId=${fileStore.sessionId}&path=${encodeURIComponent(path)}&download=true`, '_blank')
}

const handleContextMenu = (e: MouseEvent, file: FileItem) => {
  // If right clicked file is not in selection, select it (and clear others)
  if (!fileStore.selectedFiles.has(file.filename)) {
    fileStore.toggleSelection(file.filename, false)
  }

  contextMenu.value = {
    visible: true,
    x: e.clientX,
    y: e.clientY,
    file
  }
}

const handleContainerContextMenu = (e: MouseEvent) => {
  fileStore.clearSelection()
  contextMenu.value = {
    visible: true,
    x: e.clientX,
    y: e.clientY,
    file: null
  }
}

const handleCopyPath = async () => {
  const paths = Array.from(fileStore.selectedFiles).map(filename => getFullPath(filename))
  if (paths.length === 0) return

  try {
    await navigator.clipboard.writeText(paths.join('\n'))
    toast.success('已复制路径')
    closeContextMenu()
  } catch (e) {
    console.error(e)
    toast.error('复制失败')
  }
}

const closeContextMenu = () => {
  contextMenu.value.visible = false
}

const contextMenuItems = computed<MenuItem[]>(() => {
  const items: MenuItem[] = []
  const singleSelection = fileStore.selectedFiles.size === 1
  const hasSelection = fileStore.selectedFiles.size > 0

  if (!hasSelection) {
    items.push({
      label: '新建文件夹',
      icon: FolderPlusIcon,
      action: openMkdirModal
    })
    items.push({ separator: true, label: '' })
  }

  if (singleSelection) {
    const file = fileStore.files.find(f => f.filename === Array.from(fileStore.selectedFiles)[0])
    if (file) {
      items.push({
        label: '打开',
        icon: file.isDirectory ? FolderIcon : EditIcon,
        action: () => handleOpen(file)
      })

      if (file.isDirectory) {
        const fullPath = getFullPath(file.filename)
        const isFav = fileStore.isFavorite(fullPath)
        items.push({
          label: isFav ? '取消收藏' : '收藏目录',
          icon: StarIcon,
          action: () => fileStore.toggleFavorite(fullPath)
        })
      }
    }
  }

  if (hasSelection) {
    items.push({
      label: '下载',
      icon: DownloadIcon,
      action: handleDownload
    })
    items.push({
      label: '复制路径',
      icon: ClipboardIcon,
      action: handleCopyPath
    })
    items.push({ separator: true, label: '' })
    items.push({
      label: '复制',
      icon: CopyIcon,
      action: () => fileStore.copySelection()
    })
    items.push({
      label: '剪切',
      icon: ScissorsIcon,
      action: () => fileStore.cutSelection()
    })
  }

  if (fileStore.clipboard) {
    items.push({
      label: '粘贴',
      icon: ClipboardPasteIcon,
      action: handlePaste
    })
  }

  if (hasSelection) {
    items.push({ separator: true, label: '' })
    if (singleSelection) {
      items.push({
        label: '重命名',
        icon: TypeIcon,
        action: openRenameModal
      })
    }
    items.push({
      label: '删除',
      icon: Trash2Icon,
      action: () => showDeleteModal.value = true
    })
  }

  items.push({ separator: true, label: '' })
  items.push({
    label: '刷新',
    icon: RefreshCwIcon,
    action: fileStore.refresh
  })

  return items
})

const handleDrop = (e: DragEvent) => {
  if (e.dataTransfer?.files) {
    uploadFiles(e.dataTransfer.files)
  }
}
</script>
