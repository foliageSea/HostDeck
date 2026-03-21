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

    <!-- Delete Modal -->
    <Modal :show="showDeleteModal" title="确认删除" @close="emit('update:showDeleteModal', false)" @confirm="emit('confirmDelete')">
      <p class="text-muted-foreground">确定要删除选中的 {{ selectedCount }} 个项目吗？此操作无法撤销。</p>
    </Modal>
  </div>
</template>

<script setup lang="ts">
import { ref, watch, nextTick, computed } from 'vue'
import Modal from '../ui/Modal.vue'
import { Input } from '@/components/ui/input'

const props = defineProps<{
  showMkdirModal: boolean
  showRenameModal: boolean
  showDeleteModal: boolean
  newItemName: string
  selectedCount: number
}>()

const emit = defineEmits<{
  (e: 'update:showMkdirModal', value: boolean): void
  (e: 'update:showRenameModal', value: boolean): void
  (e: 'update:showDeleteModal', value: boolean): void
  (e: 'update:newItemName', value: string): void
  (e: 'confirmMkdir'): void
  (e: 'confirmRename'): void
  (e: 'confirmDelete'): void
}>()

const localNewItemName = computed({
  get: () => props.newItemName,
  set: (val) => emit('update:newItemName', val)
})

const mkdirInput = ref<any>()
const renameInput = ref<any>()

watch(() => props.showMkdirModal, (val) => {
  if (val) nextTick(() => mkdirInput.value?.$el?.focus())
})

watch(() => props.showRenameModal, (val) => {
  if (val) nextTick(() => renameInput.value?.$el?.focus())
})
</script>
