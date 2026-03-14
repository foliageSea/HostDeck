<template>
  <div class="h-full flex bg-background" @click="closeContextMenu">


    <!-- Main Content -->
    <div class="flex-1 flex flex-col min-w-0 bg-background">
      <FileToolbar 
        :currentPath="fileStore.currentPath" 
        :viewMode="fileStore.viewMode"
        @navigate="fileStore.navigate"
        @navigateUp="fileStore.navigateUp"
        @refresh="fileStore.refresh"
        @upload-files="uploadFiles"
        @mkdir="openMkdirModal"
        @toggleView="v => fileStore.viewMode = v"
      />
      
      <div class="flex-1 overflow-hidden relative" 
        @dragover.prevent 
        @drop.prevent="handleDrop"
        @contextmenu.prevent
      >
        <FileList 
          v-if="fileStore.viewMode === 'list'"
          :files="fileStore.files"
          :selectedFiles="fileStore.selectedFiles"
          @select="fileStore.toggleSelection"
          @selectAll="handleSelectAll"
          @open="handleOpen"
          @contextmenu="handleContextMenu"
        />
        <FileGrid 
          v-else
          :files="fileStore.files"
          :selectedFiles="fileStore.selectedFiles"
          @select="fileStore.toggleSelection"
          @open="handleOpen"
          @contextmenu="handleContextMenu"
        />
        
        <Loading :loading="fileStore.loading" />
        <FileUploadProgress />
      </div>
    </div>

    <!-- Context Menu -->
    <FileContextMenu 
      :visible="contextMenu.visible" 
      :x="contextMenu.x" 
      :y="contextMenu.y" 
      :items="contextMenuItems"
      @close="closeContextMenu"
    />

    <!-- Modals -->
    <Modal :show="showMkdirModal" title="新建文件夹" @close="showMkdirModal = false" @confirm="handleMkdir">
      <Input 
        v-model="newItemName" 
        placeholder="文件夹名称" 
        @keyup.enter="handleMkdir"
        ref="mkdirInput"
      />
    </Modal>
    
    <Modal :show="showRenameModal" title="重命名" @close="showRenameModal = false" @confirm="handleRename">
      <Input 
        v-model="newItemName" 
        placeholder="新名称" 
        @keyup.enter="handleRename"
        ref="renameInput"
      />
    </Modal>

    <Modal :show="showDeleteModal" title="确认删除" @close="showDeleteModal = false" @confirm="handleDelete">
      <p class="text-muted-foreground">确定要删除选中的 {{ fileStore.selectedFiles.size }} 个项目吗？此操作无法撤销。</p>
    </Modal>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, nextTick, provide } from 'vue'
import { createFileStore, FileStoreKey, type FileItem } from '../stores/file'
import { useSshStore } from '../stores/ssh'
import { useToastStore } from '../stores/toast'
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
  FolderIcon, DownloadIcon, 
  CopyIcon, ScissorsIcon, ClipboardPasteIcon, 
  EditIcon, Trash2Icon, TypeIcon, RefreshCwIcon,
  ClipboardIcon, StarIcon
} from 'lucide-vue-next'

const fileStore = createFileStore()
provide(FileStoreKey, fileStore)
const sshStore = useSshStore()
const toast = useToastStore()
const desktopStore = useDesktopStore()

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
    
    const res = await fetch(`/api/files/batch-download?sessionId=${fileStore.sessionId}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ paths })
    })
    
    if (!res.ok) throw new Error('Download failed')
    
    const blob = await res.blob()
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
         await fetch(`/api/files/copy?sessionId=${fileStore.sessionId}`, {
           method: 'POST',
           body: JSON.stringify({ source: fullSourcePath, target: fullTargetPath })
         })
       } else {
         await fetch(`/api/files/rename?sessionId=${fileStore.sessionId}`, {
            method: 'POST',
            body: JSON.stringify({ oldPath: fullSourcePath, newPath: fullTargetPath })
         })
       }
    }
    
    fileStore.refresh()
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
    const res = await fetch(`/api/files/rename?sessionId=${fileStore.sessionId}`, {
      method: 'POST',
      body: JSON.stringify({ oldPath, newPath })
    })
    if (!res.ok) throw new Error('Rename failed')
    
    toast.success('Renamed')
    showRenameModal.value = false
    fileStore.refresh()
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
    const res = await fetch(`/api/files/mkdir?sessionId=${fileStore.sessionId}`, {
      method: 'POST',
      body: JSON.stringify({ path })
    })
    if (!res.ok) throw new Error('Mkdir failed')
    
    toast.success('Directory created')
    showMkdirModal.value = false
    fileStore.refresh()
  } catch (e: any) {
    toast.error(`Mkdir failed: ${e.message}`)
  }
}

const handleDelete = async () => {
  try {
    fileStore.loading = true
    for (const filename of fileStore.selectedFiles) {
      const path = getFullPath(filename)
      // Note: delete API uses POST and query param for path based on my implementation
      // wait, let me check routes.
      // router.post('/api/files/delete', fileController.deleteFile);
      // deleteFile reads queryParameters['path']
      
      await fetch(`/api/files/delete?sessionId=${fileStore.sessionId}&path=${encodeURIComponent(path)}`, {
        method: 'POST'
      })
    }
    toast.success('Deleted')
    showDeleteModal.value = false
    fileStore.refresh()
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
        await new Promise<void>((resolve, reject) => {
          const xhr = new XMLHttpRequest()
          const url = `/api/files/upload?sessionId=${fileStore.sessionId}&path=${encodeURIComponent(fileStore.currentPath)}`
          
          xhr.open('POST', url)
          
          xhr.upload.onprogress = (e) => {
            if (e.lengthComputable) {
              const currentFileProgress = e.loaded
              const totalProgress = uploadedSize + currentFileProgress
              fileStore.uploadStatus.percent = Math.min(100, Math.round((totalProgress / totalSize) * 100))
            }
          }
          
          xhr.onload = () => {
            if (xhr.status >= 200 && xhr.status < 300) {
              resolve()
            } else {
              reject(new Error(xhr.responseText || 'Upload failed'))
            }
          }
          
          xhr.onerror = () => reject(new Error('Network error'))
          
          xhr.send(formData)
        })
        
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
      fileStore.refresh()
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
    
    if (ext && fileStore.editableExtensions.includes(ext)) {
      openEditor(file)
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

const downloadFile = async (file: FileItem) => {
  const path = getFullPath(file.filename)
  window.open(`/api/files/read?sessionId=${fileStore.sessionId}&path=${encodeURIComponent(path)}`, '_blank')
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