<script setup lang="ts">
import { computed, h, ref, watch } from 'vue'
import { type TreeOption } from 'naive-ui'
import { filesApi } from '@/api/files'
import { resolve } from '@/utils/path'
import { directoryTreeIconUrl } from './fileIcons'

interface DirectoryTreeOption extends TreeOption {
  children?: DirectoryTreeOption[]
  key: string
  label: string
  loaded?: boolean
  path: string
}

const props = defineProps<{
  connectionId?: string | null
  currentPath: string
}>()

const emit = defineEmits<{
  navigate: [path: string]
}>()

const treeData = ref<DirectoryTreeOption[]>([createRootNode()])
const expandedKeys = ref<string[]>(['/'])
const loadingError = ref('')
const loadPromises = new Map<string, Promise<boolean>>()
let loadGeneration = 0

const selectedKeys = computed(() => [props.currentPath])

function createRootNode(): DirectoryTreeOption {
  return {
    key: '/',
    label: '根目录',
    path: '/',
    isLeaf: false,
  }
}

function renderDirectoryIcon() {
  return h('img', {
    src: directoryTreeIconUrl,
    alt: '',
    'aria-hidden': 'true',
    draggable: false,
    width: 16,
    height: 16,
  })
}

function getDirectoryPaths(path: string) {
  const segments = path.split('/').filter(Boolean)
  const paths = ['/']
  let currentPath = ''

  for (const segment of segments) {
    currentPath += `/${segment}`
    paths.push(currentPath)
  }

  return paths
}

function findNode(path: string, nodes = treeData.value): DirectoryTreeOption | undefined {
  for (const node of nodes) {
    if (node.path === path) {
      return node
    }

    const match = node.children ? findNode(path, node.children) : undefined
    if (match) {
      return match
    }
  }

  return undefined
}

async function loadChildren(option: TreeOption) {
  const node = option as DirectoryTreeOption
  if (node.loaded) {
    return true
  }

  const pendingLoad = loadPromises.get(node.path)
  if (pendingLoad) {
    return pendingLoad
  }

  const connectionId = props.connectionId
  if (!connectionId) {
    return false
  }

  const generation = loadGeneration
  const loadPromise = filesApi
    .list(connectionId, node.path)
    .then((items) => {
      if (generation !== loadGeneration || connectionId !== props.connectionId) {
        return false
      }

      node.children = items
        .filter((item) => item.isDirectory && item.filename !== '.' && item.filename !== '..')
        .sort((left, right) => left.filename.localeCompare(right.filename))
        .map((item) => {
          const path = resolve(node.path, item.filename)
          return {
            key: path,
            label: item.filename,
            path,
            isLeaf: false,
          }
        })
      node.loaded = true
      loadingError.value = ''
      return true
    })
    .catch(() => {
      if (generation === loadGeneration) {
        loadingError.value = `无法读取 ${node.path}`
      }
      return false
    })
    .finally(() => {
      if (loadPromises.get(node.path) === loadPromise) {
        loadPromises.delete(node.path)
      }
    })

  loadPromises.set(node.path, loadPromise)
  return loadPromise
}

async function syncCurrentPath(path: string) {
  const paths = getDirectoryPaths(path)

  for (const directoryPath of paths) {
    const node = findNode(directoryPath)
    if (!node || !(await loadChildren(node))) {
      return
    }
  }

  expandedKeys.value = Array.from(new Set([...expandedKeys.value, ...paths]))
}

async function resetTree() {
  loadGeneration += 1
  loadPromises.clear()
  loadingError.value = ''
  treeData.value = [createRootNode()]
  expandedKeys.value = ['/']

  if (!props.connectionId) {
    return
  }

  await loadChildren(treeData.value[0])
  await syncCurrentPath(props.currentPath)
}

function handleExpandedKeys(keys: Array<string | number>) {
  expandedKeys.value = keys.map(String)
}

function handleSelectedKeys(keys: Array<string | number>) {
  const path = keys[0]
  if (path !== undefined && path !== props.currentPath) {
    emit('navigate', String(path))
  }
}

watch(
  () => props.connectionId,
  () => {
    void resetTree()
  },
  { immediate: true },
)

watch(
  () => props.currentPath,
  (path) => {
    void syncCurrentPath(path)
  },
)
</script>

<template>
  <div class="flex h-full min-h-0 flex-col">
    <NAlert v-if="loadingError" type="error" :show-icon="false" class="mb-[8px]">
      {{ loadingError }}
    </NAlert>
    <NScrollbar class="min-h-0 flex-1 app-scrollbar app-scrollbar-compact">
      <NTree
        block-line
        ellipsis
        class="pr-[10px]"
        :data="treeData"
        :expanded-keys="expandedKeys"
        :selected-keys="selectedKeys"
        :on-load="loadChildren"
        :render-prefix="renderDirectoryIcon"
        @update:expanded-keys="handleExpandedKeys"
        @update:selected-keys="handleSelectedKeys"
      />
    </NScrollbar>
  </div>
</template>
