<template>
  <div class="h-full w-full bg-background text-foreground flex flex-col">
    <div v-if="loading" class="flex-1 flex items-center justify-center">
      <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
    </div>
    <div v-else-if="error" class="flex-1 flex flex-col items-center justify-center text-destructive p-4 text-center">
      <p class="mb-2">无法读取文件</p>
      <p class="text-sm text-muted-foreground">{{ error }}</p>
      <Button @click="loadFile" variant="outline" class="mt-4">重试</Button>
    </div>
    <FileEditor
      v-else
      :filename="filename"
      :content="content"
      :language="language"
      @save="saveFile"
      @close="closeWindow"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import FileEditor from '@/components/file/FileEditor.vue'
import { Button } from '@/components/ui/button'
import { useDesktopStore } from '@/stores/desktop'
import { useToastStore } from '@/stores/toast'
import { dirname } from '@/utils/path'
import { fileApi } from '@/api/files'

const props = defineProps<{
  path: string
  sessionId: string
  windowId?: string
}>()

const desktopStore = useDesktopStore()
const toast = useToastStore()

const loading = ref(true)
const error = ref('')
const content = ref('')

const filename = computed(() => {
  return props.path.split('/').pop() || props.path
})

const language = computed(() => {
  const ext = filename.value.split('.').pop()?.toLowerCase()
  const langMap: Record<string, string> = {
    'js': 'javascript', 'ts': 'typescript', 'py': 'python', 'sh': 'shell', 'bash': 'shell', 'zsh': 'shell',
    'md': 'markdown', 'yml': 'yaml', 'rs': 'rust', 'go': 'go',
    'cpp': 'cpp', 'c': 'c', 'h': 'cpp', 'hpp': 'cpp', 'java': 'java',
    'html': 'html', 'css': 'css', 'scss': 'scss', 'less': 'less',
    'json': 'json', 'xml': 'xml', 'sql': 'sql', 'php': 'php', 'rb': 'ruby',
    'dockerfile': 'dockerfile', 'ini': 'ini', 'conf': 'ini'
  }
  return langMap[ext || ''] || ext || 'plaintext'
})

const loadFile = async () => {
  loading.value = true
  error.value = ''
  try {
    content.value = await fileApi.readFile(props.sessionId, props.path)
  } catch (e: any) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

const saveFile = async (newContent: string) => {
  try {
    const targetDir = dirname(props.path)
    const formData = new FormData()
    const blob = new Blob([newContent], { type: 'text/plain' })
    formData.append('file', blob, filename.value)

    await fileApi.uploadFile(props.sessionId, targetDir, formData)
    
    toast.success('Saved successfully')
  } catch (e: any) {
    toast.error(`Failed to save: ${e.message}`)
  }
}

const closeWindow = () => {
  if (props.windowId) {
    desktopStore.closeWindow(props.windowId)
  }
}

onMounted(() => {
  loadFile()
})
</script>
