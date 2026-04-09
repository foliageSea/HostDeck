<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { filesApi } from '@/api/files'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'

const props = defineProps<{
  path: string
  sessionId: string
  windowId?: string
}>()

const desktopStore = useDesktopStore()
const loading = ref(true)
const saving = ref(false)
const error = ref('')
const content = ref('')

const filename = computed(() => props.path.split('/').pop() || props.path)

async function loadFile() {
  loading.value = true
  error.value = ''

  try {
    content.value = await filesApi.readFile(props.sessionId, props.path)
  } catch (loadError) {
    console.error('Failed to read file', loadError)
    error.value = '文件读取失败。'
  } finally {
    loading.value = false
  }
}

async function saveFile() {
  saving.value = true
  try {
    await filesApi.writeFile(props.sessionId, props.path, content.value)
    getUiApi().message.success('文件已保存。')
  } catch (saveError) {
    console.error('Failed to save file', saveError)
    getUiApi().message.error('保存失败。')
  } finally {
    saving.value = false
  }
}

function closeWindow() {
  if (props.windowId) {
    desktopStore.closeWindow(props.windowId)
  }
}

onMounted(() => {
  void loadFile()
})
</script>

<template>
  <div class="editor-view">
    <div class="editor-toolbar">
      <div class="editor-meta">
        <strong>{{ filename }}</strong>
        <span>{{ props.path }}</span>
      </div>

      <NSpace>
        <NButton @click="loadFile">重新加载</NButton>
        <NButton type="primary" :loading="saving" @click="saveFile">保存</NButton>
        <NButton quaternary @click="closeWindow">关闭</NButton>
      </NSpace>
    </div>

    <NSpin :show="loading" class="editor-body">
      <NResult v-if="error" status="error" title="无法读取文件" :description="error">
        <template #footer>
          <NButton @click="loadFile">重试</NButton>
        </template>
      </NResult>

      <NInput
        v-else
        v-model:value="content"
        type="textarea"
        placeholder="文件内容"
        class="editor-input"
        :autosize="false"
      />
    </NSpin>
  </div>
</template>

<style scoped>
.editor-view {
  display: flex;
  flex-direction: column;
  height: 100%;
  background: rgba(15, 23, 42, 0.2);
}

.editor-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 14px;
  border-bottom: 1px solid rgba(148, 163, 184, 0.14);
}

.editor-meta {
  display: flex;
  flex-direction: column;
  min-width: 0;
  gap: 4px;
}

.editor-meta span {
  color: rgba(148, 163, 184, 0.9);
  font-size: 12px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.editor-body {
  flex: 1;
  min-height: 0;
  padding: 12px;
}

.editor-input,
.editor-input :deep(.n-input-wrapper),
.editor-input :deep(textarea) {
  height: 100%;
}

.editor-input :deep(textarea) {
  font-family: Consolas, 'Cascadia Mono', 'Courier New', monospace;
  font-size: 13px;
  line-height: 1.6;
}
</style>
