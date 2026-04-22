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
  connectionId: string
  path: string
  playlist?: MediaPlaylistItem[]
}>()

const settingsStore = useSettingsStore()
const activePath = ref(props.path)
const hasError = ref(false)
const isSidebarVisible = ref(false)
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
  () => `/api/files/read?connectionId=${props.connectionId}&path=${encodeURIComponent(activePath.value)}`,
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
  <div class="flex h-full flex-col" :class="settingsStore.isDark ? 'bg-[#020617]' : 'bg-[linear-gradient(180deg,#f8fafc_0%,#e2e8f0_100%)]'">
    <div class="media-toolbar flex items-center justify-between gap-[12px] border-b px-[14px] py-[12px]" :class="settingsStore.isDark ? 'border-[rgba(148,163,184,0.14)] text-[#e2e8f0]' : 'border-[rgba(148,163,184,0.22)] text-[#1e293b]'">
      <div class="flex min-w-0 items-baseline gap-[10px]">
        <strong class="truncate-line">{{ filename }}</strong>
        <span v-if="playlistSummary" class="flex-none text-[12px]" :class="settingsStore.isDark ? 'text-[#94a3b8]' : 'text-[#64748b]'">{{ playlistSummary }}</span>
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

    <div class="media-content flex min-h-0 flex-1 overflow-hidden">
      <div
        class="media-stage flex min-h-0 min-w-0 flex-1 items-center justify-center"
        :class="mediaType === 'video' && !hasError ? 'media-stage--video p-[8px]' : 'p-[8px]'"
      >
        <img
          v-if="mediaType === 'image' && !hasError"
          :src="fileUrl"
          :alt="filename"
          class="max-h-full max-w-full object-contain bg-black"
          @error="hasError = true"
        />

        <div v-else-if="mediaType === 'video' && !hasError" ref="videoContainerRef" class="media-video-player h-full min-h-[260px] w-full overflow-hidden rounded-[16px] bg-black"  />

        <NResult
          v-else
          status="warning"
          title="无法预览该文件"
          description="当前仅支持基础图片和视频预览。"
        />
      </div>

      <aside v-if="shouldShowSidebar" class="media-sidebar flex w-[252px] min-w-[220px] flex-col border-l" :class="settingsStore.isDark ? 'border-[rgba(148,163,184,0.14)] bg-[rgba(15,23,42,0.76)]' : 'border-[rgba(148,163,184,0.22)] bg-[rgba(248,250,252,0.82)]'">
        <div class="flex items-center justify-between gap-[10px] px-[12px] pb-[10px] pt-[12px] text-[13px] font-600" :class="settingsStore.isDark ? 'text-[#e2e8f0]' : 'text-[#1e293b]'">
          <span>文件列表</span>
          <span class="text-[12px] font-500" :class="settingsStore.isDark ? 'text-[#94a3b8]' : 'text-[#64748b]'">{{ props.playlist?.length ?? 0 }} 项</span>
        </div>

        <div class="flex min-h-0 flex-1 flex-col gap-[8px] overflow-auto px-[10px] pb-[12px]">
          <button
            v-for="(item, index) in props.playlist"
            :key="item.path"
            type="button"
            class="grid w-full cursor-pointer grid-cols-[auto_minmax(0,1fr)] items-center gap-[8px] rounded-[12px] border px-[10px] py-[9px] text-left transition-[background,border-color,color] duration-[180ms] ease-in-out"
            :class="[
              settingsStore.isDark
                ? 'border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.8)] text-[#cbd5e1] hover:border-[rgba(96,165,250,0.42)] hover:bg-[rgba(30,41,59,0.86)]'
                : 'border-[rgba(148,163,184,0.24)] bg-[rgba(255,255,255,0.88)] text-[#334155] hover:border-[rgba(37,99,235,0.36)] hover:bg-[rgba(239,246,255,0.92)]',
              index === currentIndex
                ? settingsStore.isDark
                  ? 'border-[rgba(96,165,250,0.7)] bg-[rgba(37,99,235,0.18)] text-white'
                  : 'bg-[rgba(59,130,246,0.14)] text-[#1d4ed8]'
                : '',
            ]"
            :title="item.filename"
            @click="changeFile(index)"
          >
            <span class="rounded-full px-[6px] py-[2px] text-[11px] leading-[1.4]" :class="settingsStore.isDark ? 'bg-[rgba(59,130,246,0.14)] text-[#93c5fd]' : 'bg-[rgba(37,99,235,0.1)] text-[#2563eb]'">{{ item.type === 'video' ? '视频' : '图片' }}</span>
            <span class="truncate-line">{{ item.filename }}</span>
          </button>
        </div>
      </aside>
    </div>
  </div>
</template>

<style scoped>
.media-video-player {
  flex: 1;
}

.media-video-player :deep(.xgplayer) {
  width: 100% !important;
  height: 100% !important;
  border-radius: 16px;
  background: #000;
}

.media-video-player :deep(.xgplayer-player),
.media-video-player :deep(.xgplayer-canvas),
.media-video-player :deep(.xgplayer-video-wrap) {
  width: 100% !important;
  height: 100% !important;
}

.media-video-player :deep(video) {
  width: 100%;
  height: 100%;
  object-fit: contain;
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
    inset: 0 0 0 auto;
    width: min(78vw, 280px);
    box-shadow: -20px 0 40px rgba(2, 6, 23, 0.32);
  }

  .media-stage {
    padding: 10px;
  }

  .media-stage--video {
    padding: 0;
  }
}
</style>
