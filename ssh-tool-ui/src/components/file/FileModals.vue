<template>
  <div>
    <!-- Mkdir Modal -->
    <Modal :show="showMkdirModal" title="新建文件夹" @close="emit('update:showMkdirModal', false)" @confirm="emit('confirmMkdir')">
      <Input v-model="localNewItemName" placeholder="文件夹名称" @keyup.enter="emit('confirmMkdir')" ref="mkdirInput" />
    </Modal>

    <!-- Rename Modal -->
    <Modal :show="showRenameModal" title="重命名" @close="emit('update:showRenameModal', false)" @confirm="emit('confirmRename')">
      <Input v-model="localNewItemName" placeholder="新名称" @keyup.enter="emit('confirmRename')" ref="renameInput" />
    </Modal>

    <!-- Create File Modal -->
    <Modal :show="showCreateFileModal" title="新建文件" @close="emit('update:showCreateFileModal', false)"
      @confirm="emit('confirmCreateFile')">
      <Input v-model="localNewItemName" placeholder="文件名称" @keyup.enter="emit('confirmCreateFile')" ref="createFileInput" />
    </Modal>

    <!-- Delete Modal -->
    <Modal :show="showDeleteModal" title="确认删除" @close="emit('update:showDeleteModal', false)" @confirm="emit('confirmDelete')">
      <p class="text-muted-foreground">确定要删除选中的 {{ selectedCount }} 个项目吗？此操作无法撤销。</p>
    </Modal>

    <!-- Properties Modal -->
    <Modal :show="showPropertiesModal" title="属性" @close="emit('update:showPropertiesModal', false)">
      <div v-if="selectedFile" class="space-y-3 text-sm">
        <div class="grid grid-cols-[96px,1fr] gap-2 items-start">
          <span class="text-muted-foreground">名称</span>
          <span class="break-all">{{ selectedFile.filename }}</span>
        </div>
        <div class="grid grid-cols-[96px,1fr] gap-2 items-start">
          <span class="text-muted-foreground">完整路径</span>
          <span class="break-all">{{ fullPath }}</span>
        </div>
        <div class="grid grid-cols-[96px,1fr] gap-2 items-start">
          <span class="text-muted-foreground">类型</span>
          <span>{{ selectedFile.isDirectory ? '文件夹' : fileKind }}</span>
        </div>
        <div class="grid grid-cols-[96px,1fr] gap-2 items-start">
          <span class="text-muted-foreground">大小</span>
          <span>{{ selectedFile.isDirectory ? '--' : formatSize(selectedFile.size) }}</span>
        </div>
        <div class="grid grid-cols-[96px,1fr] gap-2 items-start">
          <span class="text-muted-foreground">修改时间</span>
          <span>{{ formatDate(selectedFile.modifyTime) }}</span>
        </div>
        <div class="grid grid-cols-[96px,1fr] gap-2 items-start">
          <span class="text-muted-foreground">远端信息</span>
          <span class="break-all font-mono text-xs text-muted-foreground">{{ selectedFile.longname || '-' }}</span>
        </div>
      </div>
      <template #footer>
        <Button variant="outline" @click="emit('update:showPropertiesModal', false)">关闭</Button>
      </template>
    </Modal>
  </div>
</template>

<script setup lang="ts">
import { ref, watch, nextTick, computed } from 'vue'
import Modal from '../ui/Modal.vue'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { resolve } from '@/utils/path'
import type { FileItem } from '@/stores/file'

const props = defineProps<{
  showMkdirModal: boolean
  showRenameModal: boolean
  showDeleteModal: boolean
  showCreateFileModal: boolean
  showPropertiesModal: boolean
  newItemName: string
  selectedCount: number
  currentPath: string
  selectedFile: FileItem | null
}>()

const emit = defineEmits<{
  (e: 'update:showMkdirModal', value: boolean): void
  (e: 'update:showRenameModal', value: boolean): void
  (e: 'update:showDeleteModal', value: boolean): void
  (e: 'update:showCreateFileModal', value: boolean): void
  (e: 'update:showPropertiesModal', value: boolean): void
  (e: 'update:newItemName', value: string): void
  (e: 'confirmMkdir'): void
  (e: 'confirmRename'): void
  (e: 'confirmDelete'): void
  (e: 'confirmCreateFile'): void
}>()

const localNewItemName = computed({
  get: () => props.newItemName,
  set: (val) => emit('update:newItemName', val)
})

const mkdirInput = ref<any>()
const renameInput = ref<any>()
const createFileInput = ref<any>()

watch(() => props.showMkdirModal, (val) => {
  if (val) nextTick(() => mkdirInput.value?.$el?.focus())
})

watch(() => props.showRenameModal, (val) => {
  if (val) nextTick(() => renameInput.value?.$el?.focus())
})

watch(() => props.showCreateFileModal, (val) => {
  if (val) nextTick(() => createFileInput.value?.$el?.focus())
})

const fullPath = computed(() => {
  if (!props.selectedFile) return '-'
  return resolve(props.currentPath, props.selectedFile.filename)
})

const fileKind = computed(() => {
  if (!props.selectedFile || props.selectedFile.isDirectory) return '文件夹'
  const ext = props.selectedFile.filename.split('.').pop()?.toUpperCase()
  return ext ? `${ext} 文件` : '文件'
})

const formatDate = (isoString?: string) => {
  if (!isoString) return '-'
  const date = new Date(isoString)
  return `${date.toLocaleDateString()} ${date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`
}

const formatSize = (bytes: number) => {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`
}
</script>
