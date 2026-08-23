<script setup lang="ts">
import { Download, FolderAdd, Upload } from '@vicons/carbon'

defineProps<{
  canCompress: boolean
  canExtract: boolean
  isUploading: boolean
  selectedCount: number
}>()

const emit = defineEmits<{
  compress: []
  create: [mode: 'directory' | 'file']
  delete: []
  download: []
  extract: []
  permission: []
  rename: []
  upload: [kind: 'file' | 'directory']
}>()

const createOptions = [
  { label: '新建目录', key: 'directory' },
  { label: '新建文件', key: 'file' },
]
const uploadOptions = [
  { label: '上传文件', key: 'file' },
  { label: '上传目录', key: 'directory' },
]

function handleCreate(key: string | number) {
  if (key === 'directory' || key === 'file') emit('create', key)
}

function handleUpload(key: string | number) {
  if (key === 'directory' || key === 'file') emit('upload', key)
}
</script>

<template>
  <div class="flex w-full flex-wrap items-center justify-start gap-[12px]">
    <NDropdown trigger="click" :options="createOptions" @select="handleCreate">
      <NButton quaternary>
        <template #icon
          ><NIcon><FolderAdd /></NIcon
        ></template>
        新建
      </NButton>
    </NDropdown>
    <NDropdown
      trigger="click"
      :options="uploadOptions.map((option) => ({ ...option, disabled: isUploading }))"
      @select="handleUpload"
    >
      <NButton quaternary :disabled="isUploading" :loading="isUploading">
        <template #icon
          ><NIcon><Upload /></NIcon
        ></template>
        上传
      </NButton>
    </NDropdown>
    <NButton quaternary :disabled="!canExtract" @click="emit('extract')">解压缩</NButton>
    <NButton quaternary :disabled="!canCompress" @click="emit('compress')">压缩</NButton>
    <NButton quaternary :disabled="selectedCount !== 1" @click="emit('rename')">重命名</NButton>
    <NButton quaternary :disabled="selectedCount !== 1" @click="emit('permission')">权限</NButton>
    <NButton quaternary :disabled="selectedCount === 0" type="error" @click="emit('delete')"
      >删除</NButton
    >
    <NButton quaternary :disabled="selectedCount === 0" @click="emit('download')">
      <template #icon
        ><NIcon><Download /></NIcon
      ></template>
      下载
    </NButton>
  </div>
</template>
