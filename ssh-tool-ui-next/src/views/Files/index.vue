<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  ArrowLeft,
  ArrowRight,
  Help,
  ArrowUp,
  Download,
  FolderAdd,
  Grid,
  List,
  Renew,
  Terminal,
  Upload,
} from '@vicons/carbon'
import { filesApi, type FileItem } from '@/api/files'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { createFileStore } from '@/stores/file'
import { useSettingsStore } from '@/stores/settings'
import { useUploadCenterStore } from '@/stores/upload-center'
import { basename, resolve } from '@/utils/path'
import FileBrowserContent from './components/FileBrowserContent.vue'
import FileNameDialog from './components/FileNameDialog.vue'

const fileStore = createFileStore()
const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const uploadCenterStore = useUploadCenterStore()

const currentPathInput = ref('/')
const createDialogMode = ref<'directory' | 'file'>('directory')
const newItemName = ref('')
const renameValue = ref('')
const editingPath = ref(false)
const showCreateDialog = ref(false)
const showRenameDialog = ref(false)
const showDeleteDialog = ref(false)
const fileInputRef = ref<HTMLInputElement | null>(null)

const selectedFile = computed(() => fileStore.selectedFile)
const selectedFiles = computed(() =>
  fileStore.files.filter((file) => fileStore.selectedNames.includes(file.filename)),
)
const isUploading = computed(() => uploadCenterStore.activeTaskCount > 0)
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

function handleFileClick(file: FileItem, event: MouseEvent) {
  fileStore.selectFile(file, {
    append: event.ctrlKey || event.metaKey,
    range: event.shiftKey,
  })
}

async function openFile(file: FileItem) {
  fileStore.selectFile(file)
  if (!file.isDirectory) {
    const extension = file.filename.split('.').pop()?.toLowerCase() || ''

    if (editableExtensions.has(extension)) {
      desktopStore.openWindow('editor', {
        path: resolve(fileStore.currentPath, file.filename),
        sessionId: fileStore.sessionId,
        title: file.filename,
      })
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
        path: resolve(fileStore.currentPath, file.filename),
        playlist,
        sessionId: fileStore.sessionId,
        title: file.filename,
      })
    }

    return
  }

  await fileStore.navigateTo(file.filename)
  syncPathInput()
}

async function submitPath() {
  await fileStore.navigateTo(currentPathInput.value)
  syncPathInput()
  editingPath.value = false
}

async function navigateToPath(path: string) {
  await fileStore.navigateTo(path)
  syncPathInput()
  editingPath.value = false
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
  if (!fileStore.sessionId || !newItemName.value.trim()) {
    return
  }

  const nextPath = resolve(fileStore.currentPath, newItemName.value.trim())

  try {
    if (createDialogMode.value === 'directory') {
      await filesApi.mkdir(fileStore.sessionId, nextPath)
    } else {
      await filesApi.writeFile(fileStore.sessionId, nextPath, '')
    }

    showCreateDialog.value = false
    await fileStore.fetchFiles()
    getUiApi().message.success(createDialogMode.value === 'directory' ? '目录已创建。' : '文件已创建。')
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

async function confirmRename() {
  if (!fileStore.sessionId || !selectedFile.value || !renameValue.value.trim()) {
    return
  }

  try {
    await filesApi.rename(
      fileStore.sessionId,
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
  if (!fileStore.sessionId || selectedFiles.value.length === 0) {
    return
  }

  try {
    await Promise.all(
      selectedFiles.value.map((file) =>
        filesApi.delete(fileStore.sessionId as string, resolve(fileStore.currentPath, file.filename)),
      ),
    )

    showDeleteDialog.value = false
    fileStore.clearSelection()
    await fileStore.fetchFiles()
    getUiApi().message.success('删除成功。')
  } catch (error) {
    console.error('Failed to delete files', error)
    getUiApi().message.error('删除失败。')
  }
}

async function downloadSelectedFiles() {
  if (!fileStore.sessionId || selectedFiles.value.length === 0) {
    return
  }

  try {
    const fileSessionId = fileStore.sessionId
    let blob: Blob
    let filename: string

    if (selectedFiles.value.length === 1 && !selectedFiles.value[0]?.isDirectory) {
      const singleFile = selectedFiles.value[0]
      blob = await filesApi.download(fileSessionId, resolve(fileStore.currentPath, singleFile.filename))
      filename = basename(singleFile.filename)
    } else {
      blob = await filesApi.batchDownload(
        fileSessionId,
        selectedFiles.value.map((file) => resolve(fileStore.currentPath, file.filename)),
      )
      filename = 'download.tar.gz'
    }

    const url = window.URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = filename
    anchor.click()
    window.URL.revokeObjectURL(url)
  } catch (error) {
    console.error('Failed to download selection', error)
    getUiApi().message.error('下载失败。')
  }
}

function triggerUpload() {
  if (isUploading.value) {
    return
  }

  fileInputRef.value?.click()
}

async function handleUploadChange(event: Event) {
  if (!fileStore.sessionId) {
    return
  }

  const input = event.target as HTMLInputElement
  const files = input.files
  if (!files || files.length === 0) {
    return
  }

  const selectedUploads = Array.from(files)
  const batchId = uploadCenterStore.createBatch(fileStore.sessionId, fileStore.currentPath, selectedUploads)
  uploadCenterStore.clearBatchError(batchId)

  try {
    for (const [index, file] of selectedUploads.entries()) {
      const batch = uploadCenterStore.batches.find((item) => item.id === batchId)
      const task = batch?.tasks[index]
      if (!task) {
        continue
      }

      uploadCenterStore.updateTask(task.id, {
        loaded: 0,
        progress: 0,
        status: 'uploading',
        total: file.size,
      })

      const formData = new FormData()
      formData.append('file', file, file.name)
      await filesApi.upload(fileStore.sessionId, fileStore.currentPath, formData, (progressEvent) => {
        const total = progressEvent.total ?? file.size
        const loaded = Math.min(progressEvent.loaded, total)

        uploadCenterStore.updateTask(task.id, {
          loaded,
          progress: total > 0 ? Math.min(100, Math.round((loaded / total) * 100)) : 0,
          total,
        })
      })

      uploadCenterStore.updateTask(task.id, {
        loaded: file.size,
        progress: 100,
        status: 'success',
        total: file.size,
      })
    }

    await fileStore.fetchFiles()
    getUiApi().message.success(`已上传 ${files.length} 个文件。`)
  } catch (error) {
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
    input.value = ''
  }
}

function openTerminalHere() {
  desktopStore.openWindow('terminal', {
    cwd: fileStore.currentPath,
    title: `终端 · ${fileStore.currentPath}`,
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

  if (event.key === 'Delete' && fileStore.hasSelection) {
    event.preventDefault()
    showDeleteDialog.value = true
    return
  }

  if (event.key === 'F2' && selectedFiles.value.length === 1) {
    event.preventDefault()
    openRenameDialog()
    return
  }

  if (event.key === 'Enter' && selectedFiles.value.length === 1 && selectedFile.value) {
    event.preventDefault()
    void openFile(selectedFile.value)
  }
}

onMounted(async () => {
  await fileStore.fetchFiles('/')
  syncPathInput()
})
</script>

<template>
  <div class="files-view" :class="{ 'files-view-light': !settingsStore.isDark }" tabindex="0" @keydown="handleKeydown"
    @click.self="fileStore.clearSelection()">
    <input ref="fileInputRef" type="file" multiple hidden @change="handleUploadChange" />

    <div class="files-toolbar">
      <NSpace align="center" wrap>
        <NTooltip>
          <template #trigger>
            <NButton quaternary circle :disabled="fileStore.backHistory.length === 0" @click="navigateBack">
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
            <NButton quaternary circle :disabled="fileStore.forwardHistory.length === 0" @click="navigateForward">
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
            <NButton quaternary circle @click="navigateUp">
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
            <NButton quaternary circle @click="fileStore.fetchFiles()">
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

      <div class="toolbar-right">
        <NInput v-model:value="fileStore.search" placeholder="搜索当前目录" clearable class="search-input" />
        <NSpace align="center" size="small">
          <NPopover trigger="hover" placement="bottom-end">
            <template #trigger>
              <NButton quaternary circle>
                <template #icon>
                  <NIcon>
                    <Help />
                  </NIcon>
                </template>
              </NButton>
            </template>
            <div class="shortcut-popover">
              <div>Ctrl/Cmd + Click：多选</div>
              <div>Shift + Click：范围选择</div>
              <div>Ctrl/Cmd + A：全选</div>
              <div>Ctrl/Cmd + U：上传</div>
              <div>Ctrl/Cmd + D：下载</div>
              <div>Delete：删除</div>
              <div>F2：重命名</div>
              <div>Enter：打开选中项</div>
            </div>
          </NPopover>
          <NTooltip>
            <template #trigger>
              <NButton quaternary circle :type="fileStore.viewMode === 'list' ? 'primary' : 'default'"
                @click="fileStore.viewMode = 'list'">
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
              <NButton quaternary circle :type="fileStore.viewMode === 'grid' ? 'primary' : 'default'"
                @click="fileStore.viewMode = 'grid'">
                <template #icon>
                  <NIcon>
                    <Grid />
                  </NIcon>
                </template>
              </NButton>
            </template>
            网格视图
          </NTooltip>
        </NSpace>
      </div>
    </div>

    <div class="path-row">
      <div v-if="!editingPath" class="path-breadcrumbs">
        <NBreadcrumb>
          <NBreadcrumbItem v-for="item in breadcrumbs" :key="item.path">
            <button type="button" class="breadcrumb-link" @click="navigateToPath(item.path)">
              {{ item.label }}
            </button>
          </NBreadcrumbItem>
        </NBreadcrumb>
      </div>
      <div v-else class="path-editor">
        <NInput v-model:value="currentPathInput" placeholder="输入远程路径快速跳转" @keyup.enter="submitPath"
          @keyup.esc="stopPathEditing" @blur="stopPathEditing" />
      </div>

      <div class="path-actions">
        <NButton v-if="editingPath" type="primary" @mousedown.prevent @click="submitPath">跳转</NButton>
        <NTooltip v-else>
          <template #trigger>
            <NButton circle @click="startPathEditing">
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
            <NButton circle @click="openTerminalHere">
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

    <div class="actions-row">
      <NButton @click="openCreate('directory')">
        <template #icon>
          <NIcon>
            <FolderAdd />
          </NIcon>
        </template>
        新建目录
      </NButton>
      <NButton @click="openCreate('file')">新建文件</NButton>
      <NButton :disabled="isUploading" :loading="isUploading" @click="triggerUpload">
        <template #icon>
          <NIcon>
            <Upload />
          </NIcon>
        </template>
        上传
      </NButton>
      <NButton :disabled="selectedFiles.length !== 1" @click="openRenameDialog">重命名</NButton>
      <NButton :disabled="selectedFiles.length === 0" type="error" ghost @click="showDeleteDialog = true">删除</NButton>
      <NButton :disabled="selectedFiles.length === 0" @click="downloadSelectedFiles">
        <template #icon>
          <NIcon>
            <Download />
          </NIcon>
        </template>
        下载
      </NButton>
    </div>

    <FileBrowserContent :files="fileStore.displayFiles" :loading="fileStore.loading"
      :selected-names="fileStore.selectedNames" :view-mode="fileStore.viewMode" :format-file-size="formatFileSize"
      :format-modify-time="formatModifyTime" @click-file="handleFileClick" @open-file="openFile" />

    <NCard v-if="selectedFile" size="small" class="details-panel">
      <div class="details-title">当前选择</div>
      <div>{{ selectedFiles.length > 1 ? `已选 ${selectedFiles.length} 项` : selectedFile.filename }}</div>
      <div class="details-meta">{{ selectedFile.isDirectory ? '目录' : formatFileSize(selectedFile.size) }}</div>
      <div class="details-meta">{{ formatModifyTime(selectedFile.modifyTime) }}</div>
    </NCard>

    <FileNameDialog v-model:show="showCreateDialog" :title="createDialogMode === 'directory' ? '新建目录' : '新建文件'"
      :value="newItemName" @update:value="(value) => (newItemName = value)" @confirm="confirmCreate" />

    <FileNameDialog v-model:show="showRenameDialog" title="重命名" :value="renameValue"
      @update:value="(value) => (renameValue = value)" @confirm="confirmRename" />

    <NModal v-model:show="showDeleteDialog" preset="dialog" title="确认删除" positive-text="删除" negative-text="取消"
      @positive-click="confirmDelete" @negative-click="showDeleteDialog = false">
      删除 {{ selectedFiles.length > 1 ? `这 ${selectedFiles.length} 个项目` : '`' + (selectedFile?.filename ?? '') + '`' }}
      后不可恢复。
    </NModal>
  </div>
</template>

<style scoped>
.files-view {
  display: flex;
  flex-direction: column;
  height: 100%;
  gap: 14px;
  padding: 16px;
  background: linear-gradient(180deg, rgba(15, 23, 42, 0.14), rgba(15, 23, 42, 0.04));
  outline: none;
}

.files-toolbar,
.path-row,
.actions-row {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}

.files-toolbar,
.path-row {
  justify-content: space-between;
}

.actions-row {
  width: 100%;
  justify-content: flex-end;
}

.toolbar-right {
  display: flex;
  align-items: center;
  gap: 12px;
}

.path-breadcrumbs {
  flex: 1;
  min-width: 240px;
  overflow-x: auto;
  padding-bottom: 2px;
}

.path-editor {
  flex: 1;
  min-width: 240px;
}

.path-actions {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 12px;
  flex-wrap: wrap;
}

.search-input {
  width: min(280px, 60vw);
}

.path-editor :deep(.n-input) {
  width: 100%;
}

.breadcrumb-link {
  padding: 0;
  border: 0;
  background: transparent;
  color: inherit;
  cursor: pointer;
}

.breadcrumb-link:hover {
  color: rgba(96, 165, 250, 0.95);
}

.shortcut-popover {
  display: flex;
  flex-direction: column;
  gap: 6px;
  font-size: 12px;
  color: rgba(226, 232, 240, 0.96);
}

.details-meta,
.details-title {
  color: rgba(148, 163, 184, 0.9);
  font-size: 12px;
}

.details-panel {
  border-radius: 16px;
  background: rgba(15, 23, 42, 0.56);
}

.files-view-light {
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.68), rgba(226, 232, 240, 0.34));
}

.files-view-light .shortcut-popover {
  color: rgba(51, 65, 85, 0.96);
}

.files-view-light .details-meta,
.files-view-light .details-title {
  color: rgba(100, 116, 139, 0.92);
}

.files-view-light .details-panel {
  background: rgba(255, 255, 255, 0.84);
}
</style>
