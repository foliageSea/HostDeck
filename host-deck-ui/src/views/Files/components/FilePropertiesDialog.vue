<script setup lang="ts">
import type { FileItem } from '@/api/files'
import { formatModifyTime } from '../utils/fileFormatters'

defineProps<{
  calculatingDirectorySize: boolean
  directorySize: number | null
  file: FileItem | null
  path: string
  permission: string
  show: boolean
  sizeText: string
}>()

const emit = defineEmits<{
  calculateDirectorySize: []
  editPermission: [file: FileItem, path: string]
  'update:show': [value: boolean]
}>()
</script>

<template>
  <NModal
    :show="show"
    preset="card"
    title="属性"
    style="width: min(560px, calc(100vw - 24px))"
    @update:show="(value: boolean) => emit('update:show', value)"
  >
    <div v-if="file" class="flex flex-col gap-[12px]">
      <div class="property-row">
        <span class="property-label">名称</span>
        <span class="property-value">{{ file.filename }}</span>
      </div>
      <div class="property-row">
        <span class="property-label">类型</span>
        <span class="property-value">{{ file.isDirectory ? '目录' : '文件' }}</span>
      </div>
      <div class="property-row">
        <span class="property-label">路径</span>
        <span class="property-value break-all">{{ path }}</span>
      </div>
      <div class="property-row items-start">
        <span class="property-label pt-[5px]">大小</span>
        <div class="flex min-w-0 flex-1 flex-wrap items-center gap-[8px]">
          <span class="property-value flex-none">{{ sizeText }}</span>
          <NButton
            v-if="file.isDirectory"
            quaternary
            size="small"
            :loading="calculatingDirectorySize"
            @click="emit('calculateDirectorySize')"
          >
            {{ directorySize === null ? '计算目录大小' : '重新计算' }}
          </NButton>
        </div>
      </div>
      <div class="property-row">
        <span class="property-label">权限</span>
        <div class="flex min-w-0 flex-1 flex-wrap items-center gap-[8px]">
          <span class="property-value flex-none font-mono">{{ permission }}</span>
          <NButton quaternary size="small" @click="emit('editPermission', file, path)"
            >修改</NButton
          >
        </div>
      </div>
      <div class="property-row">
        <span class="property-label">修改时间</span>
        <span class="property-value">{{ formatModifyTime(file.modifyTime) }}</span>
      </div>
      <div class="property-row items-start">
        <span class="property-label pt-[2px]">原始信息</span>
        <span class="property-value break-all font-mono text-[12px]">{{
          file.longname || '-'
        }}</span>
      </div>
    </div>
  </NModal>
</template>
