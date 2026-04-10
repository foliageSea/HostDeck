<script setup lang="ts">
import { DocumentAdd, Folder } from '@vicons/carbon'
import type { FileItem } from '@/api/files'

defineProps<{
  files: FileItem[]
  loading: boolean
  selectedNames: string[]
  viewMode: 'list' | 'grid'
  formatFileSize: (size: number) => string
  formatModifyTime: (value?: string) => string
}>()

const emit = defineEmits<{
  clickFile: [file: FileItem, event: MouseEvent]
  openFile: [file: FileItem]
}>()
</script>

<template>
  <div class="files-content">
    <NSpin :show="loading">
      <NEmpty v-if="files.length === 0" description="当前目录没有文件" class="files-empty" />

      <div v-else-if="viewMode === 'grid'" class="file-grid">
        <button
          v-for="file in files"
          :key="file.filename"
          type="button"
          class="file-card"
          :class="{ 'file-card-active': selectedNames.includes(file.filename) }"
          @click="emit('clickFile', file, $event)"
          @dblclick="emit('openFile', file)"
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
          v-for="file in files"
          :key="file.filename"
          type="button"
          class="file-row"
          :class="{ 'file-row-active': selectedNames.includes(file.filename) }"
          @click="emit('clickFile', file, $event)"
          @dblclick="emit('openFile', file)"
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
</template>

<style scoped>
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
