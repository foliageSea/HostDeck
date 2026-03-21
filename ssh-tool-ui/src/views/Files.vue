<template>
  <div class="h-full flex bg-background" @click="closeContextMenu">

    <!-- Main Content -->
    <div class="flex-1 flex flex-col min-w-0 bg-background">
      <FileToolbar :currentPath="fileStore.currentPath" :viewMode="fileStore.viewMode" @navigate="fileStore.navigate"
        @navigateUp="fileStore.navigateUp" @refresh="fileStore.refresh" @upload-files="uploadFiles"
        @mkdir="openMkdirModal" @toggleView="v => fileStore.viewMode = v" />

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

        <FileList v-if="fileStore.viewMode === 'list'" :files="fileStore.files" :selectedFiles="fileStore.selectedFiles"
          @select="fileStore.toggleSelection" @selectAll="handleSelectAll" @open="handleOpen"
          @contextmenu="handleContextMenu" />
        <FileGrid v-else :files="fileStore.files" :selectedFiles="fileStore.selectedFiles"
          @select="fileStore.toggleSelection" @open="handleOpen" @contextmenu="handleContextMenu" />

        <Loading :loading="fileStore.loading" />
        <FileUploadProgress />
      </div>
    </div>

    <!-- Context Menu -->
    <FileContextMenu :visible="contextMenu.visible" :x="contextMenu.x" :y="contextMenu.y" :items="contextMenuItems"
      @close="closeContextMenu" />

    <!-- Modals -->
    <FileModals v-model:showMkdirModal="showMkdirModal" v-model:showRenameModal="showRenameModal"
      v-model:showDeleteModal="showDeleteModal" v-model:newItemName="newItemName"
      :selectedCount="fileStore.selectedFiles.size" @confirmMkdir="handleMkdir" @confirmRename="handleRename"
      @confirmDelete="handleDelete" />
  </div>
</template>

<script setup lang="ts">
import { onMounted, provide } from 'vue'
import { createFileStore, FileStoreKey } from '../stores/file'
import { useSshStore } from '../stores/ssh'
import { useDesktopStore } from '../stores/desktop'

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

const fileSelection = useFileSelection(fileStore)
const selectionBox = fileSelection.selectionBox
const handleMouseDown = fileSelection.handleMouseDown

const operations = useFileOperations(fileStore, desktopStore)

// Destructure for template usage
const {
  showMkdirModal,
  showRenameModal,
  showDeleteModal,
  newItemName,
  handleMkdir,
  handleRename,
  handleDelete,
  uploadFiles,
  handleDrop,
  handleOpen,
  handleSelectAll,
  openMkdirModal
} = operations

const {
  contextMenu,
  handleContextMenu,
  handleContainerContextMenu,
  closeContextMenu,
  contextMenuItems
} = useFileContextMenu(fileStore, operations)

// Initial load
onMounted(async () => {
  if (sshStore.isConnected) {
    await fileStore.initSession()
    fileStore.fetchFiles()
  }
})
</script>
