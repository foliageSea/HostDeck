<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue'
import Player, { Events, type IPlayerOptions } from 'xgplayer'
import 'xgplayer/dist/index.min.css'
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
const isSidebarVisible = ref(true)
const videoContainerRef = ref<HTMLElement | null>(null)

let playerInstance: InstanceType<typeof Player> | null = null
let playerInitToken = 0

const currentIndex = computed(() => props.playlist?.findIndex((item) => item.path === activePath.value) ?? -1)
const hasPrev = computed(() => currentIndex.value > 0)
const hasNext = computed(() => currentIndex.value >= 0 && !!props.playlist && currentIndex.value < props.playlist.length - 1)
const filename = computed(() => activePath.value.split('/').pop() || activePath.value)
const extension = computed(() => filename.value.split('.').pop()?.toLowerCase() || '')
const hasPlaylist = computed(() => !!props.playlist?.length)
const shouldShowSidebar = computed(() => hasPlaylist.value && isSidebarVisible.value)
const playlistSummary = computed(() => {
  if (!props.playlist?.length || currentIndex.value < 0) {
    return ''
  }

  return `${currentIndex.value + 1} / ${props.playlist.length}`
})

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

function toggleSidebar() {
  isSidebarVisible.value = !isSidebarVisible.value
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

function destroyPlayer() {
  if (!playerInstance) {
    return
  }

  playerInstance.destroy()
  playerInstance = null
}

async function initializePlayer() {
  const initToken = ++playerInitToken
  destroyPlayer()

  if (mediaType.value !== 'video' || hasError.value) {
    return
  }

  await nextTick()

  if (initToken !== playerInitToken || mediaType.value !== 'video' || hasError.value || !videoContainerRef.value) {
    return
  }

  const playerOptions: IPlayerOptions = {
    autoplay: true,
    cssFullscreen: true,
    download: false,
    el: videoContainerRef.value,
    fluid: true,
    height: '100%',
    lang: 'zh-cn',
    playbackRate: [0.5, 0.75, 1, 1.25, 1.5, 2],
    playsinline: true,
    url: fileUrl.value,
    videoFillMode: 'contain',
    width: '100%',
  }

  try {
    playerInstance = new Player(playerOptions)
    playerInstance.on(Events.ERROR, () => {
      hasError.value = true
    })
  } catch (error) {
    console.error('Failed to initialize xgplayer', error)
    hasError.value = true
  }
}

watch(
  () => [mediaType.value, fileUrl.value, hasError.value] as const,
  () => {
    if (mediaType.value !== 'video' || hasError.value) {
      playerInitToken += 1
      destroyPlayer()
      return
    }

    void initializePlayer()
  },
  { flush: 'post', immediate: true },
)

onBeforeUnmount(() => {
  playerInitToken += 1
  destroyPlayer()
})
</script>

<template>
  <div class="media-viewer" :class="{ 'media-viewer-light': !settingsStore.isDark }">
    <div class="media-toolbar">
      <div class="media-title">
        <strong>{{ filename }}</strong>
        <span v-if="playlistSummary">{{ playlistSummary }}</span>
      </div>

      <NSpace>
        <NButton v-if="hasPlaylist" @click="toggleSidebar">
          {{ isSidebarVisible ? '隐藏列表' : '显示列表' }}
        </NButton>
        <NButton :disabled="!hasPrev" @click="openPrevious">上一项</NButton>
        <NButton :disabled="!hasNext" @click="openNext">下一项</NButton>
        <NButton tag="a" :href="`${fileUrl}&download=true`" target="_blank">下载</NButton>
      </NSpace>
    </div>

    <div class="media-content">
      <aside v-if="shouldShowSidebar" class="media-sidebar">
        <div class="media-sidebar-header">
          <span>文件列表</span>
          <span>{{ props.playlist?.length ?? 0 }} 项</span>
        </div>

        <div class="media-sidebar-list">
          <button
            v-for="(item, index) in props.playlist"
            :key="item.path"
            type="button"
            class="playlist-item"
            :class="{ 'playlist-item-active': index === currentIndex }"
            :title="item.filename"
            @click="changeFile(index)"
          >
            <span class="playlist-item-type">{{ item.type === 'video' ? '视频' : '图片' }}</span>
            <span class="playlist-item-name">{{ item.filename }}</span>
          </button>
        </div>
      </aside>

      <div class="media-stage">
        <img
          v-if="mediaType === 'image' && !hasError"
          :src="fileUrl"
          :alt="filename"
          class="media-image"
          @error="hasError = true"
        />

        <div v-else-if="mediaType === 'video' && !hasError" ref="videoContainerRef" class="media-video-player" />

        <NResult
          v-else
          status="warning"
          title="无法预览该文件"
          description="当前仅支持基础图片和视频预览。"
        />
      </div>
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

.media-title {
  display: flex;
  align-items: baseline;
  gap: 10px;
  min-width: 0;
}

.media-title strong {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.media-title span {
  flex: none;
  color: #94a3b8;
  font-size: 12px;
}

.media-content {
  flex: 1;
  min-height: 0;
  display: flex;
  overflow: hidden;
}

.media-sidebar {
  width: 252px;
  min-width: 220px;
  display: flex;
  flex-direction: column;
  border-right: 1px solid rgba(148, 163, 184, 0.14);
  background: rgba(15, 23, 42, 0.76);
}

.media-sidebar-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  padding: 12px 12px 10px;
  color: #e2e8f0;
  font-size: 13px;
  font-weight: 600;
}

.media-sidebar-header span:last-child {
  color: #94a3b8;
  font-size: 12px;
  font-weight: 500;
}

.media-sidebar-list {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
  overflow: auto;
  padding: 0 10px 12px;
}

.media-stage {
  flex: 1;
  min-width: 0;
  min-height: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
}

.media-image {
  max-width: 100%;
  max-height: 100%;
  object-fit: contain;
}

.media-video-player {
  width: 100%;
  height: 100%;
  min-height: 260px;
  overflow: hidden;
  border-radius: 16px;
  background: #000;
}

.media-video-player :deep(.xgplayer) {
  width: 100% !important;
  height: 100% !important;
  border-radius: 16px;
  background: #000;
}

.media-video-player :deep(video) {
  object-fit: contain;
}

.playlist-item {
  width: 100%;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
  align-items: center;
  gap: 8px;
  padding: 9px 10px;
  border: 1px solid rgba(148, 163, 184, 0.16);
  border-radius: 12px;
  background: rgba(15, 23, 42, 0.8);
  color: #cbd5e1;
  cursor: pointer;
  text-align: left;
  transition: background 0.18s ease, border-color 0.18s ease, color 0.18s ease;
}

.playlist-item:hover {
  border-color: rgba(96, 165, 250, 0.42);
  background: rgba(30, 41, 59, 0.86);
}

.playlist-item-type {
  padding: 2px 6px;
  border-radius: 999px;
  background: rgba(59, 130, 246, 0.14);
  color: #93c5fd;
  font-size: 11px;
  line-height: 1.4;
}

.playlist-item-name {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.playlist-item-active {
  background: rgba(37, 99, 235, 0.18);
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

.media-viewer-light .media-title span {
  color: #64748b;
}

.media-viewer-light .media-sidebar {
  border-right-color: rgba(148, 163, 184, 0.22);
  background: rgba(248, 250, 252, 0.82);
}

.media-viewer-light .media-sidebar-header {
  color: #1e293b;
}

.media-viewer-light .media-sidebar-header span:last-child {
  color: #64748b;
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

.media-viewer-light .playlist-item:hover {
  border-color: rgba(37, 99, 235, 0.36);
  background: rgba(239, 246, 255, 0.92);
}

.media-viewer-light .playlist-item-type {
  background: rgba(37, 99, 235, 0.1);
  color: #2563eb;
}

@media (max-width: 720px) {
  .media-toolbar {
    align-items: flex-start;
    flex-direction: column;
  }

  .media-content {
    position: relative;
  }

  .media-sidebar {
    position: absolute;
    z-index: 2;
    inset: 0 auto 0 0;
    width: min(78vw, 280px);
    box-shadow: 20px 0 40px rgba(2, 6, 23, 0.32);
  }

  .media-stage {
    padding: 10px;
  }
}
</style>
