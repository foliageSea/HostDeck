<script setup lang="ts">
import { ArrowUp, FolderAdd, Renew, Search } from '@vicons/carbon'
import { computed, ref, watch } from 'vue'
import { filesApi, type FileItem } from '@/api/files'
import { dirname, resolve } from '@/utils/path'
import FileBrowserContent from './FileBrowserContent.vue'
import type { FilePickerConfirmPayload, FilePickerMode, FilePickerSelection } from './filePickerTypes'

const props = withDefaults(
  defineProps<{
    confirmText?: string
    allowCreateDirectory?: boolean
    connectionId?: string | null
    initialPath?: string
    mode?: FilePickerMode
    multiple?: boolean
    show: boolean
    title?: string
  }>(),
  {
    allowCreateDirectory: true,
    confirmText: '选择',
    connectionId: null,
    initialPath: '/',
    mode: 'file',
    multiple: false,
    title: '选择文件',
  },
)

const emit = defineEmits<{
  cancel: []
  confirm: [payload: FilePickerConfirmPayload]
  'update:show': [show: boolean]
}>()

const currentPath = ref('/')
const currentPathInput = ref('/')
const files = ref<FileItem[]>([])
const loading = ref(false)
const creatingDirectory = ref(false)
const selectedNames = ref<string[]>([])
const loadError = ref('')
const newDirectoryName = ref('')
const searchKeyword = ref('')
const showCreateDirectoryDialog = ref(false)
let loadToken = 0

const sortedFiles = computed(() =>
  [...files.value]
    .filter((file) => file.filename !== '.' && file.filename !== '..')
    .sort((left, right) => {
      if (left.isDirectory !== right.isDirectory) {
        return left.isDirectory ? -1 : 1
      }

      return left.filename.localeCompare(right.filename)
    }),
)

const displayFiles = computed(() => {
  const keyword = searchKeyword.value.trim().toLocaleLowerCase()
  if (!keyword) {
    return sortedFiles.value
  }

  return sortedFiles.value.filter((file) => file.filename.toLocaleLowerCase().includes(keyword))
})

const emptyDescription = computed(() => (searchKeyword.value.trim() ? '没有匹配的文件' : '当前目录没有文件'))

const selectedItems = computed(() => {
  const selectedNameSet = new Set(selectedNames.value)
  return displayFiles.value.filter((file) => selectedNameSet.has(file.filename))
})

const canSelectCurrentDirectory = computed(() => props.mode === 'directory' || props.mode === 'both')

const selectableItems = computed(() => selectedItems.value.filter((file) => isSelectable(file)))

const confirmDisabled = computed(() => {
  if (!props.connectionId || loading.value) {
    return true
  }

  if (canSelectCurrentDirectory.value && selectedItems.value.length === 0) {
    return false
  }

  return selectableItems.value.length === 0
})

const selectionHint = computed(() => {
  if (!props.connectionId) {
    return '请先建立 SSH 连接。'
  }

  if (props.mode === 'directory') {
    return '可选择当前目录，或选中列表中的目录后确认。'
  }

  if (props.mode === 'both') {
    return '可选择当前目录，也可选中文件或目录后确认。'
  }

  return '请选择一个文件。'
})

watch(
  () => props.show,
  (show) => {
    if (!show) {
      return
    }

    const initialPath = resolve('/', props.initialPath)
    currentPath.value = initialPath
    currentPathInput.value = initialPath
    searchKeyword.value = ''
    selectedNames.value = []
    void loadFiles(initialPath)
  },
  { immediate: true },
)

watch(
  () => props.connectionId,
  () => {
    if (props.show) {
      void loadFiles(currentPath.value)
    }
  },
)

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

function isSelectable(file: FileItem) {
  if (props.mode === 'both') {
    return true
  }

  return props.mode === 'directory' ? file.isDirectory : !file.isDirectory
}

async function loadFiles(path: string) {
  const connectionId = props.connectionId
  const token = ++loadToken
  loadError.value = ''
  selectedNames.value = []

  if (!connectionId) {
    files.value = []
    return
  }

  loading.value = true
  try {
    const targetPath = resolve('/', path)
    const response = await filesApi.list(connectionId, targetPath)
    if (token !== loadToken) {
      return
    }

    files.value = response
    if (targetPath !== currentPath.value) {
      searchKeyword.value = ''
    }
    currentPath.value = targetPath
    currentPathInput.value = targetPath
  } catch (error) {
    if (token !== loadToken) {
      return
    }

    console.error('Failed to load selectable files', error)
    files.value = []
    loadError.value = '目录加载失败，请检查连接或路径。'
  } finally {
    if (token === loadToken) {
      loading.value = false
    }
  }
}

function handleShowUpdate(show: boolean) {
  emit('update:show', show)
  if (!show) {
    emit('cancel')
  }
}

function handleFileClick(file: FileItem, event: MouseEvent) {
  if (props.multiple && (event.ctrlKey || event.metaKey)) {
    selectedNames.value = selectedNames.value.includes(file.filename)
      ? selectedNames.value.filter((name) => name !== file.filename)
      : [...selectedNames.value, file.filename]
    return
  }

  selectedNames.value = [file.filename]
}

function handleSelectNames(names: string[]) {
  selectedNames.value = props.multiple ? names : names.slice(-1)
}

async function handleOpenFile(file: FileItem) {
  if (file.isDirectory) {
    await navigateTo(resolve(currentPath.value, file.filename))
    return
  }

  if (isSelectable(file)) {
    selectedNames.value = [file.filename]
    confirmSelection()
  }
}

async function navigateTo(path: string) {
  await loadFiles(resolve(currentPath.value, path))
}

async function navigateUp() {
  await navigateTo(dirname(currentPath.value))
}

async function submitPath() {
  await navigateTo(currentPathInput.value)
}

function openCreateDirectoryDialog() {
  newDirectoryName.value = ''
  showCreateDirectoryDialog.value = true
}

async function confirmCreateDirectory() {
  const connectionId = props.connectionId
  const directoryName = newDirectoryName.value.trim()
  if (!connectionId || creatingDirectory.value) {
    return
  }

  if (!directoryName) {
    loadError.value = '目录名称不能为空。'
    return
  }

  if (directoryName.includes('/')) {
    loadError.value = '目录名称不能包含 /。'
    return
  }

  creatingDirectory.value = true
  loadError.value = ''
  try {
    await filesApi.mkdir(connectionId, resolve(currentPath.value, directoryName))
    showCreateDirectoryDialog.value = false
    await loadFiles(currentPath.value)
    selectedNames.value = [directoryName]
  } catch (error) {
    console.error('Failed to create selectable directory', error)
    loadError.value = '目录创建失败，请检查权限或名称是否重复。'
  } finally {
    creatingDirectory.value = false
  }
}

function buildSelection(file: FileItem | null): FilePickerSelection {
  return {
    currentPath: currentPath.value,
    item: file,
    path: file ? resolve(currentPath.value, file.filename) : currentPath.value,
  }
}

function confirmSelection() {
  if (confirmDisabled.value) {
    return
  }

  const selections = selectableItems.value.map((file) => buildSelection(file))
  const nextSelections = selections.length > 0 ? selections : [buildSelection(null)]

  emit('confirm', {
    currentPath: currentPath.value,
    selections: props.multiple ? nextSelections : nextSelections.slice(0, 1),
  })
  emit('update:show', false)
}
</script>

<template>
  <NModal
    :show="show"
    preset="card"
    :title="title"
    style="width: min(900px, calc(100vw - 24px))"
    @update:show="handleShowUpdate"
  >
    <div class="flex h-[min(680px,calc(100vh-180px))] min-h-[420px] flex-col gap-[12px]">
      <div class="flex flex-col gap-[10px] md:flex-row md:items-center">
        <div class="flex min-w-0 flex-1 items-center gap-[8px]">
          <NButton quaternary round size="small" :disabled="loading || currentPath === '/'" @click="navigateUp">
            <template #icon>
              <NIcon>
                <ArrowUp />
              </NIcon>
            </template>
          </NButton>
          <NInput
            v-model:value="currentPathInput"
            :disabled="loading || !connectionId"
            placeholder="输入远程路径"
            @keyup.enter="submitPath"
          />
          <NInput
            v-model:value="searchKeyword"
            clearable
            :disabled="loading || !connectionId"
            placeholder="搜索文件名"
            class="md:max-w-[240px]"
          >
            <template #prefix>
              <NIcon>
                <Search />
              </NIcon>
            </template>
          </NInput>
          <NButton quaternary round size="small" :disabled="loading || !connectionId" @click="loadFiles(currentPath)">
            <template #icon>
              <NIcon>
                <Renew />
              </NIcon>
            </template>
          </NButton>
          <NButton
            v-if="allowCreateDirectory"
            quaternary
            round
            size="small"
            :disabled="loading || !connectionId"
            @click="openCreateDirectoryDialog"
          >
            <template #icon>
              <NIcon>
                <FolderAdd />
              </NIcon>
            </template>
            新建目录
          </NButton>
        </div>
      </div>

      <NAlert v-if="loadError" type="error" :show-icon="false">
        {{ loadError }}
      </NAlert>
      <NAlert v-else type="info" :show-icon="false">
        {{ selectionHint }}
      </NAlert>

      <FileBrowserContent
        :files="displayFiles"
        :empty-description="emptyDescription"
        :loading="loading"
        :selected-names="selectedNames"
        view-mode="list"
        :format-file-size="formatFileSize"
        :format-modify-time="formatModifyTime"
        @click-file="handleFileClick"
        @context-blank="selectedNames = []"
        @context-file="handleFileClick"
        @open-file="handleOpenFile"
        @select-names="handleSelectNames"
      />

      <div class="flex flex-col gap-[10px] border-t border-[rgba(148,163,184,0.22)] pt-[12px] md:flex-row md:items-center md:justify-between">
        <div class="min-w-0 text-[13px] text-[rgba(100,116,139,0.92)]">
          <span v-if="selectedItems.length > 0">已选 {{ selectedItems.length }} 项</span>
          <span v-else-if="canSelectCurrentDirectory">将选择当前目录：{{ currentPath }}</span>
          <span v-else>未选择文件</span>
        </div>
        <div class="flex justify-end gap-[8px]">
          <NButton quaternary round @click="handleShowUpdate(false)">取消</NButton>
          <NButton quaternary round type="primary" :disabled="confirmDisabled" @click="confirmSelection">
            {{ confirmText }}
          </NButton>
        </div>
      </div>
    </div>

    <NModal
      v-model:show="showCreateDirectoryDialog"
      preset="card"
      title="新建目录"
      style="width: min(420px, calc(100vw - 24px))"
    >
      <div class="flex flex-col gap-[14px]">
        <NInput
          v-model:value="newDirectoryName"
          placeholder="输入目录名称"
          :disabled="creatingDirectory"
          @keyup.enter="confirmCreateDirectory"
        />
        <div class="flex justify-end gap-[8px]">
          <NButton quaternary round :disabled="creatingDirectory" @click="showCreateDirectoryDialog = false">取消</NButton>
          <NButton quaternary round type="primary" :loading="creatingDirectory" @click="confirmCreateDirectory">创建</NButton>
        </div>
      </div>
    </NModal>
  </NModal>
</template>
