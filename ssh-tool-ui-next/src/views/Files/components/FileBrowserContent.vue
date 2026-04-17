<script setup lang="ts">
import {
  Archive,
  Certificate,
  Code,
  Csv,
  DataBase,
  Document,
  DocumentAudio,
  DocumentBlank,
  DocumentPdf,
  DocumentProtected,
  DocumentUnknown,
  DocumentVideo,
  DocumentWordProcessor,
  Encryption,
  FolderOpen,
  Gif,
  Html,
  Image,
} from '@vicons/carbon'
import { computed, onBeforeUnmount, ref } from 'vue'
import type { Component } from 'vue'
import type { FileItem } from '@/api/files'
import { useSettingsStore } from '@/stores/settings'

const settingsStore = useSettingsStore()

type FileIconTone = 'folder' | 'image' | 'video' | 'audio' | 'code' | 'document' | 'archive' | 'data' | 'secure' | 'default'

interface FileIconMeta {
  icon: Component
  tone: FileIconTone
}

const folderIcon: FileIconMeta = { icon: FolderOpen, tone: 'folder' }
const defaultFileIcon: FileIconMeta = { icon: DocumentUnknown, tone: 'default' }

const filenameIcons: Record<string, FileIconMeta> = {
  '.bash_history': { icon: DocumentBlank, tone: 'document' },
  '.bash_profile': { icon: Code, tone: 'code' },
  '.bashrc': { icon: Code, tone: 'code' },
  '.dockerignore': { icon: Code, tone: 'code' },
  '.env': { icon: Encryption, tone: 'secure' },
  '.gitconfig': { icon: DocumentProtected, tone: 'secure' },
  '.gitignore': { icon: Code, tone: 'code' },
  '.npmrc': { icon: DocumentProtected, tone: 'secure' },
  '.profile': { icon: Code, tone: 'code' },
  '.ssh': folderIcon,
  '.vimrc': { icon: Code, tone: 'code' },
  'dockerfile': { icon: Code, tone: 'code' },
  'license': { icon: Document, tone: 'document' },
  'makefile': { icon: Code, tone: 'code' },
  'readme': { icon: Document, tone: 'document' },
}

const extensionIcons: Record<string, FileIconMeta> = {
  '7z': { icon: Archive, tone: 'archive' },
  'aac': { icon: DocumentAudio, tone: 'audio' },
  'ape': { icon: DocumentAudio, tone: 'audio' },
  'apng': { icon: Image, tone: 'image' },
  'apk': { icon: Archive, tone: 'archive' },
  'asc': { icon: Encryption, tone: 'secure' },
  'avi': { icon: DocumentVideo, tone: 'video' },
  'avif': { icon: Image, tone: 'image' },
  'bash': { icon: Code, tone: 'code' },
  'bat': { icon: Code, tone: 'code' },
  'bmp': { icon: Image, tone: 'image' },
  'bz2': { icon: Archive, tone: 'archive' },
  'c': { icon: Code, tone: 'code' },
  'cer': { icon: Certificate, tone: 'secure' },
  'cert': { icon: Certificate, tone: 'secure' },
  'conf': { icon: DocumentProtected, tone: 'secure' },
  'config': { icon: DocumentProtected, tone: 'secure' },
  'cpp': { icon: Code, tone: 'code' },
  'crt': { icon: Certificate, tone: 'secure' },
  'cs': { icon: Code, tone: 'code' },
  'csr': { icon: Certificate, tone: 'secure' },
  'css': { icon: Code, tone: 'code' },
  'csv': { icon: Csv, tone: 'data' },
  'cxx': { icon: Code, tone: 'code' },
  'dart': { icon: Code, tone: 'code' },
  'db': { icon: DataBase, tone: 'data' },
  'deb': { icon: Archive, tone: 'archive' },
  'doc': { icon: DocumentWordProcessor, tone: 'document' },
  'docx': { icon: DocumentWordProcessor, tone: 'document' },
  'env': { icon: Encryption, tone: 'secure' },
  'fish': { icon: Code, tone: 'code' },
  'flac': { icon: DocumentAudio, tone: 'audio' },
  'flv': { icon: DocumentVideo, tone: 'video' },
  'gif': { icon: Gif, tone: 'image' },
  'go': { icon: Code, tone: 'code' },
  'gz': { icon: Archive, tone: 'archive' },
  'h': { icon: Code, tone: 'code' },
  'heic': { icon: Image, tone: 'image' },
  'heif': { icon: Image, tone: 'image' },
  'hpp': { icon: Code, tone: 'code' },
  'htm': { icon: Html, tone: 'code' },
  'html': { icon: Html, tone: 'code' },
  'ico': { icon: Image, tone: 'image' },
  'ini': { icon: DocumentProtected, tone: 'secure' },
  'java': { icon: Code, tone: 'code' },
  'jar': { icon: Archive, tone: 'archive' },
  'jpeg': { icon: Image, tone: 'image' },
  'jpg': { icon: Image, tone: 'image' },
  'js': { icon: Code, tone: 'code' },
  'json': { icon: Code, tone: 'code' },
  'jsx': { icon: Code, tone: 'code' },
  'key': { icon: Encryption, tone: 'secure' },
  'kt': { icon: Code, tone: 'code' },
  'kts': { icon: Code, tone: 'code' },
  'less': { icon: Code, tone: 'code' },
  'log': { icon: DocumentBlank, tone: 'document' },
  'lua': { icon: Code, tone: 'code' },
  'm4a': { icon: DocumentAudio, tone: 'audio' },
  'm4v': { icon: DocumentVideo, tone: 'video' },
  'md': { icon: Document, tone: 'document' },
  'mkv': { icon: DocumentVideo, tone: 'video' },
  'mov': { icon: DocumentVideo, tone: 'video' },
  'mp3': { icon: DocumentAudio, tone: 'audio' },
  'mp4': { icon: DocumentVideo, tone: 'video' },
  'odp': { icon: DocumentWordProcessor, tone: 'document' },
  'ods': { icon: Csv, tone: 'data' },
  'odt': { icon: DocumentWordProcessor, tone: 'document' },
  'ogg': { icon: DocumentAudio, tone: 'audio' },
  'ogv': { icon: DocumentVideo, tone: 'video' },
  'opus': { icon: DocumentAudio, tone: 'audio' },
  'p12': { icon: Certificate, tone: 'secure' },
  'pem': { icon: Certificate, tone: 'secure' },
  'pdf': { icon: DocumentPdf, tone: 'document' },
  'pfx': { icon: Certificate, tone: 'secure' },
  'php': { icon: Code, tone: 'code' },
  'png': { icon: Image, tone: 'image' },
  'ppt': { icon: DocumentWordProcessor, tone: 'document' },
  'pptx': { icon: DocumentWordProcessor, tone: 'document' },
  'ps1': { icon: Code, tone: 'code' },
  'py': { icon: Code, tone: 'code' },
  'rar': { icon: Archive, tone: 'archive' },
  'rb': { icon: Code, tone: 'code' },
  'rpm': { icon: Archive, tone: 'archive' },
  'rs': { icon: Code, tone: 'code' },
  'rtf': { icon: DocumentWordProcessor, tone: 'document' },
  'sass': { icon: Code, tone: 'code' },
  'scala': { icon: Code, tone: 'code' },
  'scss': { icon: Code, tone: 'code' },
  'sh': { icon: Code, tone: 'code' },
  'sqlite': { icon: DataBase, tone: 'data' },
  'sqlite3': { icon: DataBase, tone: 'data' },
  'sql': { icon: DataBase, tone: 'data' },
  'svg': { icon: Image, tone: 'image' },
  'swift': { icon: Code, tone: 'code' },
  'tar': { icon: Archive, tone: 'archive' },
  'tgz': { icon: Archive, tone: 'archive' },
  'tif': { icon: Image, tone: 'image' },
  'tiff': { icon: Image, tone: 'image' },
  'toml': { icon: Code, tone: 'code' },
  'ts': { icon: Code, tone: 'code' },
  'tsv': { icon: Csv, tone: 'data' },
  'tsx': { icon: Code, tone: 'code' },
  'txt': { icon: DocumentBlank, tone: 'document' },
  'vue': { icon: Code, tone: 'code' },
  'war': { icon: Archive, tone: 'archive' },
  'wav': { icon: DocumentAudio, tone: 'audio' },
  'webm': { icon: DocumentVideo, tone: 'video' },
  'webp': { icon: Image, tone: 'image' },
  'wma': { icon: DocumentAudio, tone: 'audio' },
  'wmv': { icon: DocumentVideo, tone: 'video' },
  'xls': { icon: Csv, tone: 'data' },
  'xlsx': { icon: Csv, tone: 'data' },
  'xml': { icon: Code, tone: 'code' },
  'xz': { icon: Archive, tone: 'archive' },
  'yaml': { icon: Code, tone: 'code' },
  'yml': { icon: Code, tone: 'code' },
  'zip': { icon: Archive, tone: 'archive' },
  'zsh': { icon: Code, tone: 'code' },
}

function getFileExtension(filename: string) {
  const parts = filename.toLowerCase().split('.')
  return parts.length > 1 ? parts[parts.length - 1] : ''
}

function getFileIcon(file: FileItem) {
  if (file.isDirectory) {
    return folderIcon
  }

  const normalizedName = file.filename.toLowerCase()
  return filenameIcons[normalizedName] ?? extensionIcons[getFileExtension(normalizedName)] ?? defaultFileIcon
}

function getFileIconClass(file: FileItem) {
  return `file-icon-${getFileIcon(file).tone}`
}

const props = defineProps<{
  files: FileItem[]
  loading: boolean
  selectedNames: string[]
  viewMode: 'list' | 'grid'
  formatFileSize: (size: number) => string
  formatModifyTime: (value?: string) => string
}>()

const emit = defineEmits<{
  clickFile: [file: FileItem, event: MouseEvent]
  contextBlank: [event: MouseEvent]
  contextFile: [file: FileItem, event: MouseEvent]
  openFile: [file: FileItem]
  selectNames: [names: string[]]
}>()

interface SelectionState {
  active: boolean
  append: boolean
  baseNames: string[]
  pointerId: number
  startX: number
  startY: number
  currentX: number
  currentY: number
}

const contentRef = ref<HTMLElement | null>(null)
const selectionState = ref<SelectionState | null>(null)

const selectionBoxStyle = computed(() => {
  const state = selectionState.value
  const content = contentRef.value
  if (!state?.active || !content) {
    return {}
  }

  const contentRect = content.getBoundingClientRect()
  const left = Math.min(state.startX, state.currentX) - contentRect.left + content.scrollLeft
  const top = Math.min(state.startY, state.currentY) - contentRect.top + content.scrollTop
  const width = Math.abs(state.currentX - state.startX)
  const height = Math.abs(state.currentY - state.startY)

  return {
    left: `${left}px`,
    top: `${top}px`,
    width: `${width}px`,
    height: `${height}px`,
  }
})

function isFileTarget(target: EventTarget | null) {
  return target instanceof Element && Boolean(target.closest('[data-file-name]'))
}

function isRectIntersecting(left: DOMRect, right: DOMRect) {
  return left.left < right.right && left.right > right.left && left.top < right.bottom && left.bottom > right.top
}

function getNamesInsideSelection(state: SelectionState) {
  const content = contentRef.value
  if (!content) {
    return []
  }

  const selectionRect = new DOMRect(
    Math.min(state.startX, state.currentX),
    Math.min(state.startY, state.currentY),
    Math.abs(state.currentX - state.startX),
    Math.abs(state.currentY - state.startY),
  )

  const nextNames: string[] = []
  content.querySelectorAll<HTMLElement>('[data-file-name]').forEach((element) => {
    if (isRectIntersecting(selectionRect, element.getBoundingClientRect())) {
      const fileName = element.dataset.fileName
      if (fileName) {
        nextNames.push(fileName)
      }
    }
  })

  return nextNames
}

function emitSelection(state: SelectionState) {
  const selectedNames = getNamesInsideSelection(state)
  if (!state.append) {
    emit('selectNames', selectedNames)
    return
  }

  emit('selectNames', Array.from(new Set([...state.baseNames, ...selectedNames])))
}

function handlePointerDown(event: PointerEvent) {
  if (event.button !== 0 || props.loading || isFileTarget(event.target)) {
    return
  }

  const target = event.currentTarget
  if (!(target instanceof HTMLElement)) {
    return
  }

  target.setPointerCapture(event.pointerId)
  selectionState.value = {
    active: false,
    append: event.ctrlKey || event.metaKey,
    baseNames: [...props.selectedNames],
    pointerId: event.pointerId,
    startX: event.clientX,
    startY: event.clientY,
    currentX: event.clientX,
    currentY: event.clientY,
  }
}

function handlePointerMove(event: PointerEvent) {
  const state = selectionState.value
  if (!state || state.pointerId !== event.pointerId) {
    return
  }

  state.currentX = event.clientX
  state.currentY = event.clientY

  if (!state.active && Math.hypot(state.currentX - state.startX, state.currentY - state.startY) >= 4) {
    state.active = true
  }

  if (state.active) {
    emitSelection(state)
  }
}

function finishSelection(event: PointerEvent) {
  const state = selectionState.value
  if (!state || state.pointerId !== event.pointerId) {
    return
  }

  if (event.currentTarget instanceof HTMLElement && event.currentTarget.hasPointerCapture(event.pointerId)) {
    event.currentTarget.releasePointerCapture(event.pointerId)
  }

  if (!state.active && !state.append) {
    emit('selectNames', [])
  }

  selectionState.value = null
}

function handleFileContextMenu(file: FileItem, event: MouseEvent) {
  event.preventDefault()
  emit('contextFile', file, event)
}

function handleBlankContextMenu(event: MouseEvent) {
  if (isFileTarget(event.target)) {
    return
  }

  event.preventDefault()
  emit('contextBlank', event)
}

onBeforeUnmount(() => {
  selectionState.value = null
})
</script>

<template>
  <div
    ref="contentRef"
    class="files-content"
    :class="{ 'files-content-light': !settingsStore.isDark, 'files-content-selecting': selectionState?.active }"
    @contextmenu="handleBlankContextMenu"
    @pointercancel="finishSelection"
    @pointerdown="handlePointerDown"
    @pointermove="handlePointerMove"
    @pointerup="finishSelection"
  >
    <div v-if="loading" class="files-loading">
      <NSpin size="large" />
    </div>

    <template v-else>
      <NEmpty v-if="files.length === 0" description="当前目录没有文件" class="files-empty" />

      <div v-else-if="viewMode === 'grid'" class="file-grid">
        <button
          v-for="file in files"
          :key="file.filename"
          :data-file-name="file.filename"
          type="button"
          class="file-card"
          :class="{ 'file-card-active': selectedNames.includes(file.filename) }"
          @click="emit('clickFile', file, $event)"
          @contextmenu="handleFileContextMenu(file, $event)"
          @dblclick="emit('openFile', file)"
        >
          <NIcon size="28" class="file-icon" :class="getFileIconClass(file)">
            <component :is="getFileIcon(file).icon" />
          </NIcon>
          <div class="file-name">{{ file.filename }}</div>
          <div class="file-meta">{{ file.isDirectory ? '目录' : formatFileSize(file.size) }}</div>
        </button>
      </div>

      <div v-else class="file-list">
        <button
          v-for="file in files"
          :key="file.filename"
          :data-file-name="file.filename"
          type="button"
          class="file-row"
          :class="{ 'file-row-active': selectedNames.includes(file.filename) }"
          @click="emit('clickFile', file, $event)"
          @contextmenu="handleFileContextMenu(file, $event)"
          @dblclick="emit('openFile', file)"
        >
          <div class="file-row-main">
            <NIcon size="20" class="file-icon" :class="getFileIconClass(file)">
              <component :is="getFileIcon(file).icon" />
            </NIcon>
            <span class="file-name">{{ file.filename }}</span>
          </div>
          <span class="file-row-size">{{ file.isDirectory ? '-' : formatFileSize(file.size) }}</span>
          <span class="file-row-time">{{ formatModifyTime(file.modifyTime) }}</span>
        </button>
      </div>
    </template>

    <div v-if="selectionState?.active" class="selection-box" :style="selectionBoxStyle" />
  </div>
</template>

<style scoped>
.files-content {
  position: relative;
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: 4px;
}

.files-content-selecting {
  user-select: none;
}

.selection-box {
  position: absolute;
  z-index: 5;
  pointer-events: none;
  border: 1px solid rgba(96, 165, 250, 0.72);
  border-radius: 8px;
  background: rgba(96, 165, 250, 0.16);
  box-shadow: 0 0 0 1px rgba(96, 165, 250, 0.16) inset;
}

.files-empty {
  height: 100%;
  min-height: 260px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.files-loading {
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
  align-items: center;
  justify-content: center;
  gap: 10px;
  min-height: 130px;
  padding: 14px;
  border-radius: 16px;
  text-align: center;
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

.file-icon {
  flex: 0 0 auto;
}

.file-icon-folder {
  color: rgba(96, 165, 250, 0.96);
}

.file-icon-image {
  color: rgba(192, 132, 252, 0.96);
}

.file-icon-video {
  color: rgba(251, 113, 133, 0.96);
}

.file-icon-audio {
  color: rgba(52, 211, 153, 0.96);
}

.file-icon-code {
  color: rgba(34, 211, 238, 0.96);
}

.file-icon-document {
  color: rgba(165, 180, 252, 0.96);
}

.file-icon-archive {
  color: rgba(251, 146, 60, 0.96);
}

.file-icon-data {
  color: rgba(250, 204, 21, 0.96);
}

.file-icon-secure {
  color: rgba(251, 191, 36, 0.96);
}

.file-icon-default {
  color: rgba(148, 163, 184, 0.96);
}

.file-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 100%;
}

.file-meta,
.file-row-size,
.file-row-time {
  color: rgba(148, 163, 184, 0.9);
  font-size: 12px;
}

.files-content-light .file-card,
.files-content-light .file-row {
  border-color: rgba(148, 163, 184, 0.22);
  background: rgba(255, 255, 255, 0.84);
}

.files-content-light .file-card:hover,
.files-content-light .file-row:hover,
.files-content-light .file-card-active,
.files-content-light .file-row-active {
  border-color: rgba(59, 130, 246, 0.34);
  background: rgba(219, 234, 254, 0.68);
}

.files-content-light .file-meta,
.files-content-light .file-row-size,
.files-content-light .file-row-time {
  color: rgba(100, 116, 139, 0.92);
}

.files-content-light .file-icon-folder {
  color: rgba(37, 99, 235, 0.94);
}

.files-content-light .file-icon-image {
  color: rgba(147, 51, 234, 0.94);
}

.files-content-light .file-icon-video {
  color: rgba(225, 29, 72, 0.94);
}

.files-content-light .file-icon-audio {
  color: rgba(5, 150, 105, 0.94);
}

.files-content-light .file-icon-code {
  color: rgba(8, 145, 178, 0.94);
}

.files-content-light .file-icon-document {
  color: rgba(79, 70, 229, 0.94);
}

.files-content-light .file-icon-archive {
  color: rgba(234, 88, 12, 0.94);
}

.files-content-light .file-icon-data {
  color: rgba(202, 138, 4, 0.94);
}

.files-content-light .file-icon-secure {
  color: rgba(180, 83, 9, 0.94);
}

.files-content-light .file-icon-default {
  color: rgba(100, 116, 139, 0.94);
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
