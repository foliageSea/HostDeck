<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import type { FileItem } from '@/api/files'
import { resolve } from '@/utils/path'
import { getFileIcon, getFilePreviewType } from './fileIcons'

const props = defineProps<{
  connectionId?: string | null
  currentPath?: string
  file: FileItem
  variant: 'grid' | 'list'
}>()

const previewReady = ref(false)
const previewFailed = ref(false)
const previewType = computed(() => getFilePreviewType(props.file))
const mediaUrl = computed(() => {
  if (!props.connectionId || !props.currentPath || !previewType.value) {
    return ''
  }

  const params = new URLSearchParams({
    connectionId: props.connectionId,
    path: resolve(props.currentPath, props.file.filename),
  })
  return `/api/files/read?${params.toString()}`
})
const canPreview = computed(() => Boolean(mediaUrl.value) && !previewFailed.value)

watch(mediaUrl, () => {
  previewReady.value = false
  previewFailed.value = false
})

function handleVideoMetadata(event: Event) {
  const video = event.currentTarget
  if (!(video instanceof HTMLVideoElement)) {
    return
  }

  // A tiny seek reliably paints the opening frame in browsers that leave time 0 blank.
  if (video.duration > 0) {
    video.currentTime = Math.min(0.01, video.duration)
  }
}
</script>

<template>
  <div
    class="file-media-preview relative flex flex-none items-center justify-center overflow-hidden"
    :class="
      variant === 'grid' ? 'h-[76px] w-full rounded-[10px]' : 'h-[36px] w-[44px] rounded-[7px]'
    "
  >
    <img
      v-if="canPreview && previewType === 'image'"
      :alt="file.filename"
      class="object-cover transition-opacity duration-150"
      :class="[
        variant === 'grid' ? 'h-[60px] w-[60px] rounded-[8px]' : 'h-[28px] w-[28px] rounded-[5px]',
        previewReady ? 'opacity-100' : 'opacity-0',
      ]"
      decoding="async"
      loading="lazy"
      :src="mediaUrl"
      @error="previewFailed = true"
      @load="previewReady = true"
    />
    <video
      v-else-if="canPreview && previewType === 'video'"
      :aria-label="`${file.filename} 视频预览`"
      class="pointer-events-none object-cover transition-opacity duration-150"
      :class="[
        variant === 'grid' ? 'h-[60px] w-[60px] rounded-[8px]' : 'h-[28px] w-[28px] rounded-[5px]',
        previewReady ? 'opacity-100' : 'opacity-0',
      ]"
      muted
      playsinline
      preload="metadata"
      :src="mediaUrl"
      @error="previewFailed = true"
      @loadeddata="previewReady = true"
      @loadedmetadata="handleVideoMetadata"
      @seeked="previewReady = true"
    />
    <img
      v-if="!canPreview || !previewReady"
      alt=""
      aria-hidden="true"
      class="file-type-icon absolute object-contain"
      :class="variant === 'grid' ? 'h-[60px] w-[60px]' : 'h-[28px] w-[28px]'"
      decoding="async"
      draggable="false"
      :src="getFileIcon(file).src"
    />
  </div>
</template>
