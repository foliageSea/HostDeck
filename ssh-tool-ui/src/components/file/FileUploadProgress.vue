<template>
  <div v-if="uploadStatus.uploading" class="fixed bottom-4 right-4 z-50 w-80 bg-background border rounded-lg shadow-lg overflow-hidden">
    <div class="px-4 py-3 border-b flex items-center justify-between bg-muted/50">
      <h3 class="font-medium text-sm truncate max-w-[200px]">正在上传 {{ uploadStatus.currentFilename }}</h3>
      <span class="text-xs text-muted-foreground">{{ uploadStatus.current }} / {{ uploadStatus.total }}</span>
    </div>
    <div class="p-4 space-y-3">
      <div class="flex items-center justify-between text-xs text-muted-foreground mb-1">
        <span>总体进度</span>
        <span>{{ uploadStatus.percent }}%</span>
      </div>
      <Progress :model-value="uploadStatus.percent" class="h-2" />
      
      <div class="text-xs text-muted-foreground mt-2 flex justify-between">
        <span>成功: {{ uploadStatus.success }}</span>
        <span>失败: {{ uploadStatus.failed }}</span>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { useFileStore } from '@/stores/file'
import { Progress } from '@/components/ui/progress'
import { toRefs } from 'vue'

const fileStore = useFileStore()
const { uploadStatus } = toRefs(fileStore)
</script>
