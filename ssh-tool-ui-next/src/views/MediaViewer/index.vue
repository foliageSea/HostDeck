<script setup lang="ts">
import { computed, ref } from 'vue'
import { useSettingsStore } from '@/stores/settings'

interface MediaPlaylistItem {
  path: string
  filename: string
  type: 'image' | 'video'
}

const props = defineProps<{
  path: string
  sessionId: string
  playlist?: MediaPlaylistItem[]
}>()

const settingsStore = useSettingsStore()
const activePath = ref(props.path)
const hasError = ref(false)

const currentIndex = computed(() => props.playlist?.findIndex((item) => item.path === activePath.value) ?? -1)
const hasPrev = computed(() => currentIndex.value > 0)
const hasNext = computed(() => currentIndex.value >= 0 && !!props.playlist && currentIndex.value < props.playlist.length - 1)
const filename = computed(() => activePath.value.split('/').pop() || activePath.value)
const extension = computed(() => filename.value.split('.').pop()?.toLowerCase() || '')

const mediaType = computed<'image' | 'video' | 'unknown'>(() => {
  const imageExtensions = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'ico']
  const videoExtensions = ['mp4', 'webm', 'ogg', 'mov', 'mkv', 'avi']

  if (imageExtensions.includes(extension.value)) {
    return 'image'
  }

  if (videoExtensions.includes(extension.value)) {
    return 'video'
  }

  return 'unknown'
})

const fileUrl = computed(
  () => `/api/files/read?sessionId=${props.sessionId}&path=${encodeURIComponent(activePath.value)}`,
)

function changeFile(index: number) {
  if (!props.playlist || !props.playlist[index]) {
    return
  }

  activePath.value = props.playlist[index].path
  hasError.value = false
}

function openPrevious() {
  if (hasPrev.value) {
    changeFile(currentIndex.value - 1)
  }
}

function openNext() {
  if (hasNext.value) {
    changeFile(currentIndex.value + 1)
  }
}
</script>

<template>
  <div class="media-viewer" :class="{ 'media-viewer-light': !settingsStore.isDark }">
    <div class="media-toolbar">
      <div>
        <strong>{{ filename }}</strong>
      </div>

      <NSpace>
        <NButton :disabled="!hasPrev" @click="openPrevious">上一项</NButton>
        <NButton :disabled="!hasNext" @click="openNext">下一项</NButton>
        <NButton tag="a" :href="`${fileUrl}&download=true`" target="_blank">下载</NButton>
      </NSpace>
    </div>

    <div class="media-stage">
      <img
        v-if="mediaType === 'image' && !hasError"
        :src="fileUrl"
        :alt="filename"
        class="media-image"
        @error="hasError = true"
      />

      <video
        v-else-if="mediaType === 'video' && !hasError"
        :src="fileUrl"
        class="media-video"
        controls
        autoplay
        @error="hasError = true"
      />

      <NResult
        v-else
        status="warning"
        title="无法预览该文件"
        description="当前仅支持基础图片和视频预览。"
      />
    </div>

    <div v-if="props.playlist && props.playlist.length > 1" class="media-playlist">
      <button
        v-for="(item, index) in props.playlist"
        :key="item.path"
        type="button"
        class="playlist-item"
        :class="{ 'playlist-item-active': index === currentIndex }"
        @click="changeFile(index)"
      >
        {{ item.filename }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.media-viewer {
  display: flex;
  flex-direction: column;
  height: 100%;
  background: #020617;
}

.media-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 14px;
  border-bottom: 1px solid rgba(148, 163, 184, 0.14);
  color: #e2e8f0;
}

.media-stage {
  flex: 1;
  min-height: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 12px;
}

.media-image,
.media-video {
  max-width: 100%;
  max-height: 100%;
  object-fit: contain;
}

.media-playlist {
  display: flex;
  gap: 8px;
  padding: 12px;
  overflow: auto;
  border-top: 1px solid rgba(148, 163, 184, 0.14);
}

.playlist-item {
  padding: 8px 12px;
  border: 1px solid rgba(148, 163, 184, 0.16);
  border-radius: 999px;
  background: rgba(15, 23, 42, 0.8);
  color: #cbd5e1;
  white-space: nowrap;
  cursor: pointer;
}

.playlist-item-active {
  border-color: rgba(96, 165, 250, 0.7);
  color: #fff;
}

.media-viewer-light {
  background: linear-gradient(180deg, #f8fafc 0%, #e2e8f0 100%);
}

.media-viewer-light .media-toolbar {
  border-bottom-color: rgba(148, 163, 184, 0.22);
  color: #1e293b;
}

.media-viewer-light .media-playlist {
  border-top-color: rgba(148, 163, 184, 0.22);
}

.media-viewer-light .playlist-item {
  border-color: rgba(148, 163, 184, 0.24);
  background: rgba(255, 255, 255, 0.88);
  color: #334155;
}

.media-viewer-light .playlist-item-active {
  background: rgba(59, 130, 246, 0.14);
  color: #1d4ed8;
}
</style>
