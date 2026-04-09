<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { Download, DocumentAdd, Folder, FolderAdd, Terminal, Upload } from '@vicons/carbon'
import { filesApi, type FileItem } from '@/api/files'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { createFileStore } from '@/stores/file'
import { basename, resolve } from '@/utils/path'

const fileStore = createFileStore()
const desktopStore = useDesktopStore()

const currentPathInput = ref('/')
const createDialogMode = ref<'directory' | 'file'>('directory')
const newItemName = ref('')
const renameValue = ref('')
const showCreateDialog = ref(false)
const showRenameDialog = ref(false)
const showDeleteDialog = ref(false)
const fileInputRef = ref<HTMLInputElement | null>(null)

const selectedFile = computed(() => fileStore.selectedFile)
const selectedFiles = computed(() =>
  fileStore.files.filter((file) => fileStore.selectedNames.includes(file.filename)),
)

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

  try {
    for (const file of Array.from(files)) {
      const formData = new FormData()
      formData.append('file', file, file.name)
      await filesApi.upload(fileStore.sessionId, fileStore.currentPath, formData)
    }

    await fileStore.fetchFiles()
    getUiApi().message.success(`已上传 ${files.length} 个文件。`)
  } catch (error) {
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
  await fileStore.initSession()
  await fileStore.fetchFiles('/')
  syncPathInput()
})
</script>

<template>
  <div class="files-view" tabindex="0" @keydown="handleKeydown" @click.self="fileStore.clearSelection()">
    <input ref="fileInputRef" type="file" multiple hidden @change="handleUploadChange" />

    <div class="files-toolbar">
      <NSpace align="center" wrap>
        <NButton quaternary :disabled="fileStore.backHistory.length === 0" @click="fileStore.navigateBack()">返回</NButton>
        <NButton quaternary :disabled="fileStore.forwardHistory.length === 0" @click="fileStore.navigateForward()">前进</NButton>
        <NButton quaternary @click="fileStore.navigateUp(); syncPathInput()">上级</NButton>
        <NButton quaternary @click="fileStore.fetchFiles()">刷新</NButton>
      </NSpace>

      <div class="toolbar-right">
        <NInput v-model:value="fileStore.search" placeholder="搜索当前目录" clearable class="search-input" />
        <NRadioGroup
          :value="fileStore.viewMode"
          size="small"
          @update:value="(value: 'list' | 'grid') => (fileStore.viewMode = value)"
        >
          <NRadioButton value="list">列表</NRadioButton>
          <NRadioButton value="grid">网格</NRadioButton>
        </NRadioGroup>
      </div>
    </div>

    <div class="path-row">
      <NInput v-model:value="currentPathInput" placeholder="输入远程路径" @keyup.enter="submitPath" />
      <NButton type="primary" @click="submitPath">打开</NButton>
      <NButton @click="openTerminalHere">
        <template #icon>
          <NIcon><Terminal /></NIcon>
        </template>
        终端
      </NButton>
    </div>

    <div class="actions-row">
      <NButton @click="openCreate('directory')">
        <template #icon>
          <NIcon><FolderAdd /></NIcon>
        </template>
        新建目录
      </NButton>
      <NButton @click="openCreate('file')">
        <template #icon>
          <NIcon><DocumentAdd /></NIcon>
        </template>
        新建文件
      </NButton>
      <NButton @click="triggerUpload">
        <template #icon>
          <NIcon><Upload /></NIcon>
        </template>
        上传
      </NButton>
      <NButton :disabled="selectedFiles.length !== 1" @click="openRenameDialog">重命名</NButton>
      <NButton :disabled="selectedFiles.length === 0" type="error" ghost @click="showDeleteDialog = true">删除</NButton>
      <NButton :disabled="selectedFiles.length === 0" @click="downloadSelectedFiles">
        <template #icon>
          <NIcon><Download /></NIcon>
        </template>
        下载
      </NButton>
    </div>

    <div class="selection-hint">
      支持 `Ctrl/Cmd + Click` 多选，`Shift + Click` 范围选择，`Ctrl/Cmd + A` 全选，`Delete` 删除，`F2` 重命名。
    </div>

    <div class="files-content">
      <NSpin :show="fileStore.loading">
        <NEmpty v-if="fileStore.displayFiles.length === 0" description="当前目录没有文件" class="files-empty" />

        <div v-else-if="fileStore.viewMode === 'grid'" class="file-grid">
          <button
            v-for="file in fileStore.displayFiles"
            :key="file.filename"
            type="button"
            class="file-card"
            :class="{ 'file-card-active': fileStore.selectedNames.includes(file.filename) }"
            @click="handleFileClick(file, $event)"
            @dblclick="openFile(file)"
          >
            <NIcon size="28">
              <Folder v-if="file.isDirectory" />
              <DocumentAdd v-else />
            </NIcon>
            <div class="file-name">{{ file.filename }}</div>
            <div class="file-meta">{{ file.isDirectory ? '目录' : formatFileSize(file.size) }}</div>
          </button>
        </div>

        <div v-else class="file-list">
          <button
            v-for="file in fileStore.displayFiles"
            :key="file.filename"
            type="button"
            class="file-row"
            :class="{ 'file-row-active': fileStore.selectedNames.includes(file.filename) }"
            @click="handleFileClick(file, $event)"
            @dblclick="openFile(file)"
          >
            <div class="file-row-main">
              <NIcon size="20">
                <Folder v-if="file.isDirectory" />
                <DocumentAdd v-else />
              </NIcon>
              <span class="file-name">{{ file.filename }}</span>
            </div>
            <span class="file-row-size">{{ file.isDirectory ? '-' : formatFileSize(file.size) }}</span>
            <span class="file-row-time">{{ formatModifyTime(file.modifyTime) }}</span>
          </button>
        </div>
      </NSpin>
    </div>

    <NCard v-if="selectedFile" size="small" class="details-panel">
      <div class="details-title">当前选择</div>
      <div>{{ selectedFiles.length > 1 ? `已选 ${selectedFiles.length} 项` : selectedFile.filename }}</div>
      <div class="details-meta">{{ selectedFile.isDirectory ? '目录' : formatFileSize(selectedFile.size) }}</div>
      <div class="details-meta">{{ formatModifyTime(selectedFile.modifyTime) }}</div>
    </NCard>

    <NModal
      v-model:show="showCreateDialog"
      preset="card"
      :title="createDialogMode === 'directory' ? '新建目录' : '新建文件'"
      class="file-dialog"
    >
      <NSpace vertical>
        <NInput v-model:value="newItemName" placeholder="输入名称" @keyup.enter="confirmCreate" />
        <NSpace justify="end">
          <NButton @click="showCreateDialog = false">取消</NButton>
          <NButton type="primary" @click="confirmCreate">确认</NButton>
        </NSpace>
      </NSpace>
    </NModal>

    <NModal v-model:show="showRenameDialog" preset="card" title="重命名" class="file-dialog">
      <NSpace vertical>
        <NInput v-model:value="renameValue" placeholder="输入新名称" @keyup.enter="confirmRename" />
        <NSpace justify="end">
          <NButton @click="showRenameDialog = false">取消</NButton>
          <NButton type="primary" @click="confirmRename">确认</NButton>
        </NSpace>
      </NSpace>
    </NModal>

    <NModal
      v-model:show="showDeleteDialog"
      preset="dialog"
      title="确认删除"
      positive-text="删除"
      negative-text="取消"
      @positive-click="confirmDelete"
      @negative-click="showDeleteDialog = false"
    >
      删除 {{ selectedFiles.length > 1 ? `这 ${selectedFiles.length} 个项目` : '`' + (selectedFile?.filename ?? '') + '`' }} 后不可恢复。
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
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
}

.toolbar-right {
  display: flex;
  align-items: center;
  gap: 12px;
}

.search-input {
  width: min(280px, 60vw);
}

.path-row :deep(.n-input) {
  flex: 1;
  min-width: 240px;
}

.selection-hint {
  color: rgba(148, 163, 184, 0.92);
  font-size: 12px;
}

.files-content {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: 4px;
}

.files-empty {
  height: 100%;
  min-height: 260px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.file-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(148px, 1fr));
  gap: 12px;
}

.file-card,
.file-row {
  border: 1px solid rgba(148, 163, 184, 0.16);
  background: rgba(15, 23, 42, 0.62);
  color: inherit;
  cursor: pointer;
  transition: 160ms ease;
}

.file-card:hover,
.file-row:hover,
.file-card-active,
.file-row-active {
  border-color: rgba(96, 165, 250, 0.55);
  background: rgba(30, 41, 59, 0.86);
}

.file-card {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 10px;
  min-height: 130px;
  padding: 14px;
  border-radius: 16px;
  text-align: left;
}

.file-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.file-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 120px 180px;
  align-items: center;
  gap: 12px;
  padding: 12px 14px;
  border-radius: 14px;
  text-align: left;
}

.file-row-main {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

.file-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.file-meta,
.file-row-size,
.file-row-time,
.details-meta,
.details-title {
  color: rgba(148, 163, 184, 0.9);
  font-size: 12px;
}

.details-panel {
  border-radius: 16px;
  background: rgba(15, 23, 42, 0.56);
}

.file-dialog {
  width: min(440px, calc(100vw - 24px));
}

@media (max-width: 860px) {
  .file-row {
    grid-template-columns: minmax(0, 1fr);
  }

  .file-row-size,
  .file-row-time {
    display: none;
  }
}
</style>
