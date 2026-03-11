<template>
  <div class="h-full flex flex-col relative bg-white dark:bg-gray-900" @click="closeContextMenu">
    <FileToolbar 
      :currentPath="fileStore.currentPath" 
      :viewMode="fileStore.viewMode"
      @navigate="fileStore.navigate"
      @navigateUp="fileStore.navigateUp"
      @refresh="fileStore.refresh"
      @upload="triggerUpload"
      @mkdir="openMkdirModal"
      @toggleView="v => fileStore.viewMode = v"
    />
    
    <div class="flex-1 overflow-hidden relative" 
      @dragover.prevent 
      @drop.prevent="handleDrop"
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
      <input 
        v-model="newItemName" 
        class="border border-gray-300 dark:border-gray-600 rounded p-2 w-full bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:ring-2 focus:ring-blue-500 outline-none" 
        placeholder="文件夹名称" 
        @keyup.enter="handleMkdir"
        ref="mkdirInput"
      />
    </Modal>
    
    <Modal :show="showRenameModal" title="重命名" @close="showRenameModal = false" @confirm="handleRename">
      <input 
        v-model="newItemName" 
        class="border border-gray-300 dark:border-gray-600 rounded p-2 w-full bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:ring-2 focus:ring-blue-500 outline-none" 
        placeholder="新名称" 
        @keyup.enter="handleRename"
        ref="renameInput"
      />
    </Modal>

    <Modal :show="showDeleteModal" title="确认删除" @close="showDeleteModal = false" @confirm="handleDelete">
      <p class="text-gray-700 dark:text-gray-300">确定要删除选中的 {{ fileStore.selectedFiles.size }} 个项目吗？此操作无法撤销。</p>
    </Modal>

    <!-- Editor Overlay -->
    <div v-if="showEditor" class="fixed inset-0 z-50 bg-white dark:bg-gray-900">
      <FileEditor 
        :filename="editorFile.filename" 
        :content="editorContent" 
        :language="editorLanguage"
        @close="showEditor = false" 
        @save="handleSaveFile" 
      />
    </div>
    
    <!-- Hidden File Input -->
    <input type="file" ref="fileInput" multiple style="display: none" @change="handleUpload" />
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, nextTick } from 'vue'
import { useFileStore, type FileItem } from '../stores/file'
import { useSshStore } from '../stores/ssh'
import { useToastStore } from '../stores/toast'
import FileToolbar from '../components/file/FileToolbar.vue'
import FileList from '../components/file/FileList.vue'
import FileGrid from '../components/file/FileGrid.vue'
import FileContextMenu, { type MenuItem } from '../components/file/FileContextMenu.vue'
import FileEditor from '../components/file/FileEditor.vue'
import Modal from '../components/ui/Modal.vue'
import Loading from '../components/ui/Loading.vue'
import { 
  FolderIcon, FileIcon, DownloadIcon, UploadIcon, 
  CopyIcon, ScissorsIcon, ClipboardPasteIcon, 
  EditIcon, Trash2Icon, RefreshCwIcon, TypeIcon
} from 'lucide-vue-next'

const fileStore = useFileStore()
const sshStore = useSshStore()
const toast = useToastStore()

// State
const contextMenu = ref({ visible: false, x: 0, y: 0, file: null as FileItem | null })
const showMkdirModal = ref(false)
const showRenameModal = ref(false)
const showDeleteModal = ref(false)
const showEditor = ref(false)
const newItemName = ref('')
const editorFile = ref({ filename: '', path: '' })
const editorContent = ref('')
const editorLanguage = ref('plaintext')
const fileInput = ref<HTMLInputElement>()
const mkdirInput = ref<HTMLInputElement>()
const renameInput = ref<HTMLInputElement>()

// Initial load
onMounted(() => {
  if (sshStore.isConnected) {
    fileStore.fetchFiles()
  }
})

// Methods
const getFullPath = (filename: string) => {
  if (fileStore.currentPath === '/' || fileStore.currentPath === '.') return filename.startsWith('/') ? filename : (fileStore.currentPath === '.' ? filename : '/' + filename)
  // Cleaner logic:
  let base = fileStore.currentPath
  if (base === '.') base = '' // relative to current work dir? No, currentPath should be absolute usually.
  // If currentPath is '.', it means we are at home or initial dir.
  // Let's assume currentPath is always valid path string.
  if (base.endsWith('/')) return base + filename
  return base + '/' + filename
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
    
    const res = await fetch(`/api/files/batch-download?sessionId=${sshStore.sessionId}`, {
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
       const fullSourcePath = (sourcePath === '/' ? '' : sourcePath) + '/' + filename
       const fullTargetPath = (fileStore.currentPath === '/' ? '' : fileStore.currentPath) + '/' + filename
       
       if (action === 'copy') {
         await fetch(`/api/files/copy?sessionId=${sshStore.sessionId}`, {
           method: 'POST',
           body: JSON.stringify({ source: fullSourcePath, target: fullTargetPath })
         })
       } else {
         await fetch(`/api/files/rename?sessionId=${sshStore.sessionId}`, {
            method: 'POST',
            body: JSON.stringify({ oldPath: fullSourcePath, newPath: fullTargetPath })
         })
       }
    }
    
    toast.success(action === 'copy' ? 'Copied' : 'Moved')
    fileStore.refresh()
    if (action === 'move') fileStore.clipboard = null
  } catch (e: any) {
    toast.error(`Paste failed: ${e.message}`)
  } finally {
    fileStore.loading = false
  }
}

const openRenameModal = () => {
  const filename = Array.from(fileStore.selectedFiles)[0]
  newItemName.value = filename
  showRenameModal.value = true
  nextTick(() => renameInput.value?.focus())
}

const handleRename = async () => {
  if (!newItemName.value) return
  const oldName = Array.from(fileStore.selectedFiles)[0]
  const oldPath = getFullPath(oldName)
  const newPath = getFullPath(newItemName.value)
  
  try {
    const res = await fetch(`/api/files/rename?sessionId=${sshStore.sessionId}`, {
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
  nextTick(() => mkdirInput.value?.focus())
}

const handleMkdir = async () => {
  if (!newItemName.value) return
  const path = getFullPath(newItemName.value)
  
  try {
    const res = await fetch(`/api/files/mkdir?sessionId=${sshStore.sessionId}`, {
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
      
      await fetch(`/api/files/delete?sessionId=${sshStore.sessionId}&path=${encodeURIComponent(path)}`, {
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

const triggerUpload = () => {
  fileInput.value?.click()
}

const uploadFiles = async (files: FileList) => {
  if (!files || files.length === 0) return

  fileStore.loading = true
  try {
    const formData = new FormData()
    for (let i = 0; i < files.length; i++) {
      formData.append('file', files[i])
    }
    
    const res = await fetch(`/api/files/upload?sessionId=${sshStore.sessionId}&path=${encodeURIComponent(fileStore.currentPath)}`, {
      method: 'POST',
      body: formData
    })
    
    if (!res.ok) throw new Error('Upload failed')
    
    toast.success(`Uploaded ${files.length} files`)
    fileStore.refresh()
  } catch (e: any) {
    toast.error(`Upload failed: ${e.message}`)
  } finally {
    fileStore.loading = false
  }
}

const handleUpload = async (e: Event) => {
  const input = e.target as HTMLInputElement
  if (input.files) {
    await uploadFiles(input.files)
    input.value = ''
  }
}


const handleOpen = async (file: FileItem) => {
  if (file.isDirectory) {
    fileStore.navigate(file.filename)
  } else {
    // Check file extension
    const ext = file.filename.split('.').pop()?.toLowerCase()
    const textExts = ['txt', 'md', 'json', 'js', 'ts', 'vue', 'html', 'css', 'py', 'java', 'c', 'cpp', 'h', 'go', 'rs', 'sh', 'yaml', 'yml', 'xml', 'conf', 'ini', 'log']
    
    if (ext && textExts.includes(ext)) {
      openEditor(file)
    } else {
      downloadFile(file)
    }
  }
}

const openEditor = async (file: FileItem) => {
  try {
    fileStore.loading = true
    const path = getFullPath(file.filename)
    const res = await fetch(`/api/files/read?sessionId=${sshStore.sessionId}&path=${encodeURIComponent(path)}`)
    if (!res.ok) throw new Error('Failed to read file')
    
    // Read as text
    const text = await res.text()
    editorContent.value = text
    editorFile.value = { filename: file.filename, path }
    
    // Detect language
    const ext = file.filename.split('.').pop()?.toLowerCase()
    const langMap: Record<string, string> = {
      'js': 'javascript', 'ts': 'typescript', 'py': 'python', 'sh': 'shell',
      'md': 'markdown', 'yml': 'yaml', 'rs': 'rust', 'go': 'go'
    }
    editorLanguage.value = langMap[ext || ''] || ext || 'plaintext'
    
    showEditor.value = true
  } catch (e: any) {
    toast.error(`Failed to open file: ${e.message}`)
  } finally {
    fileStore.loading = false
  }
}

const handleSaveFile = async (content: string) => {
  try {
    fileStore.loading = true
    const res = await fetch(`/api/files/upload?sessionId=${sshStore.sessionId}&path=${encodeURIComponent(fileStore.currentPath)}`, {
      method: 'POST',
      body: createFormData(editorFile.value.filename, content)
    })
    if (!res.ok) throw new Error('Failed to save file')
    toast.success('Saved successfully')
    showEditor.value = false
    fileStore.refresh()
  } catch (e: any) {
    toast.error(`Failed to save: ${e.message}`)
  } finally {
    fileStore.loading = false
  }
}

const createFormData = (filename: string, content: string) => {
  const formData = new FormData()
  const blob = new Blob([content], { type: 'text/plain' })
  formData.append('file', blob, filename)
  return formData
}

const downloadFile = async (file: FileItem) => {
  const path = getFullPath(file.filename)
  window.open(`/api/files/read?sessionId=${sshStore.sessionId}&path=${encodeURIComponent(path)}`, '_blank')
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
    }
  }
  
  if (hasSelection) {
    items.push({ 
      label: '下载', 
      icon: DownloadIcon, 
      action: handleDownload 
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
