<template>
  <div class="h-full flex bg-background" @click="closeContextMenu" @keydown="handleKeydown" tabindex="0" ref="rootRef">

    <!-- Main Content -->
    <div class="flex-1 flex flex-col min-w-0 bg-background">
      <FileToolbar :currentPath="fileStore.currentPath" :viewMode="fileStore.viewMode"
        :canNavigateBack="fileStore.backHistory.length > 0" :canNavigateForward="fileStore.forwardHistory.length > 0"
        :searchQuery="fileStore.searchQuery" :sortBy="fileStore.sortBy" :sortOrder="fileStore.sortOrder"
        :filterType="fileStore.filterType" @navigate="fileStore.navigateTo" @navigateUp="fileStore.navigateUp"
        @navigateBack="fileStore.navigateBack" @navigateForward="fileStore.navigateForward"
        @refresh="fileStore.refresh" @upload-files="uploadFiles" @mkdir="openMkdirModal"
        @createFile="openCreateFileModal" @toggleView="v => fileStore.viewMode = v"
        @open-terminal="operations.openTerminalHere" @updateSearchQuery="v => fileStore.searchQuery = v"
        @updateSortBy="v => fileStore.sortBy = v" @toggleSortOrder="toggleSortOrder"
        @updateFilterType="v => fileStore.filterType = v" />

      <div class="flex-1 overflow-hidden relative select-none" @dragover.prevent @drop.prevent="handleDrop"
        @contextmenu.prevent="handleContainerContextMenu" @mousedown="handleMouseDown"
        :ref="(el: any) => fileSelection.containerRef.value = el">

        <!-- Selection Box -->
        <div v-if="selectionBox.visible" class="absolute border border-primary bg-primary/20 z-50 pointer-events-none"
          :style="{
            left: selectionBox.x + 'px',
            top: selectionBox.y + 'px',
            width: selectionBox.width + 'px',
            height: selectionBox.height + 'px'
          }">
        </div>

        <FileList v-if="fileStore.viewMode === 'list'" :files="fileStore.displayFiles" :selectedFiles="fileStore.selectedFiles"
          @select="handleSelect" @selectAll="handleSelectAll" @open="handleOpen"
          @contextmenu="handleContextMenu" />
        <FileGrid v-else :files="fileStore.displayFiles" :selectedFiles="fileStore.selectedFiles"
          @select="handleSelect" @open="handleOpen" @contextmenu="handleContextMenu" />

        <Loading :loading="fileStore.loading" />
        <FileUploadProgress />
      </div>
    </div>

    <!-- Context Menu -->
    <FileContextMenu :visible="contextMenu.visible" :x="contextMenu.x" :y="contextMenu.y" :items="contextMenuItems"
      @close="closeContextMenu" />

     <!-- Modals -->
      <FileModals v-model:showMkdirModal="showMkdirModal" v-model:showRenameModal="showRenameModal"
      v-model:showDeleteModal="showDeleteModal" v-model:showCreateFileModal="showCreateFileModal"
      v-model:showPropertiesModal="showPropertiesModal" v-model:newItemName="newItemName"
      :selectedCount="fileStore.selectedFiles.size" :currentPath="fileStore.currentPath"
      :selectedFile="selectedFileForProperties"
      @confirmMkdir="handleMkdir" @confirmRename="handleRename" @confirmDelete="handleDelete"
      @confirmCreateFile="handleCreateFile" />
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, provide, ref } from 'vue'
import { createFileStore, FileStoreKey } from '../stores/file'
import { useSshStore } from '../stores/ssh'
import { useDesktopStore } from '../stores/desktop'
import type { FileItem } from '../stores/file'

import FileToolbar from '../components/file/FileToolbar.vue'
import FileList from '../components/file/FileList.vue'
import FileGrid from '../components/file/FileGrid.vue'
import FileContextMenu from '../components/file/FileContextMenu.vue'
import FileUploadProgress from '../components/file/FileUploadProgress.vue'
import FileModals from '../components/file/FileModals.vue'
import Loading from '../components/ui/Loading.vue'

import { useFileSelection } from '../composables/file/useFileSelection'
import { useFileOperations } from '../composables/file/useFileOperations'
import { useFileContextMenu } from '../composables/file/useFileContextMenu'

const fileStore = createFileStore()
provide(FileStoreKey, fileStore)
const sshStore = useSshStore()
const desktopStore = useDesktopStore()
const rootRef = ref<HTMLElement | null>(null)

const fileSelection = useFileSelection(fileStore)
const selectionBox = fileSelection.selectionBox
const handleMouseDown = fileSelection.handleMouseDown

const operations = useFileOperations(fileStore, desktopStore)

// Destructure for template usage
const {
  showMkdirModal,
  showRenameModal,
  showDeleteModal,
  showCreateFileModal,
  showPropertiesModal,
  newItemName,
  handleMkdir,
  handleRename,
  handleDelete,
  handleCreateFile,
  uploadFiles,
  handleDrop,
  handleOpen,
  handleSelectAll,
  openMkdirModal,
  openCreateFileModal
} = operations

const {
  contextMenu,
  handleContextMenu,
  handleContainerContextMenu,
  closeContextMenu,
  contextMenuItems
} = useFileContextMenu(fileStore, operations)

const selectedFileForProperties = computed(() => {
  const selected = Array.from(fileStore.selectedFiles)[0]
  if (!selected) return null
  return fileStore.files.find((file: FileItem) => file.filename === selected) || null
})

const handleSelect = (file: FileItem, event: MouseEvent) => {
  const multi = event.ctrlKey || event.metaKey
  const range = event.shiftKey

  if (range) {
    fileStore.selectRange(file.filename, fileStore.displayFiles)
    return
  }

  fileStore.toggleSelection(file.filename, multi)
}

const toggleSortOrder = () => {
  fileStore.sortOrder = fileStore.sortOrder === 'asc' ? 'desc' : 'asc'
}

const handleKeydown = (event: KeyboardEvent) => {
  const target = event.target as HTMLElement | null
  if (target) {
    const tagName = target.tagName.toLowerCase()
    if (tagName === 'input' || tagName === 'textarea' || target.isContentEditable) {
      return
    }
  }

  const hasSelection = fileStore.selectedFiles.size > 0
  const singleSelection = fileStore.selectedFiles.size === 1

  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'a') {
    event.preventDefault()
    handleSelectAll()
    return
  }

  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'c') {
    if (!hasSelection) return
    event.preventDefault()
    fileStore.copySelection()
    return
  }

  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'x') {
    if (!hasSelection) return
    event.preventDefault()
    fileStore.cutSelection()
    return
  }

  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'v') {
    if (!fileStore.clipboard) return
    event.preventDefault()
    operations.handlePaste()
    return
  }

  if (event.key === 'Delete' && hasSelection) {
    event.preventDefault()
    operations.openDeleteModal()
    return
  }

  if (event.key === 'F2' && singleSelection) {
    event.preventDefault()
    operations.openRenameModal()
    return
  }

  if (event.key === 'Enter' && singleSelection) {
    const selected = selectedFileForProperties.value
    if (!selected) return
    event.preventDefault()
    handleOpen(selected)
  }
}

// Initial load
onMounted(async () => {
  if (sshStore.isConnected) {
    await fileStore.initSession()
    fileStore.fetchFiles()
  }
  rootRef.value?.focus()
})
</script>
