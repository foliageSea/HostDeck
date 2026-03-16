<template>
  <div class="h-full w-full bg-background flex relative overflow-hidden">
    <!-- Main Content -->
    <div class="flex-1 flex flex-col items-center justify-center relative overflow-hidden bg-black/5 dark:bg-black/40">
      <template v-if="type === 'image'">
        <img :src="fileUrl" class="max-w-full max-h-full object-contain select-none" :alt="filename"
          @error="handleError" />
      </template>
      <template v-else-if="type === 'video'">
        <div :id="playerId" class="w-full h-full"></div>
      </template>

      <div v-if="error"
        class="text-destructive flex flex-col items-center gap-2 p-4 text-center z-10 bg-background/80 rounded-lg absolute">
        <p>无法加载媒体文件</p>
        <Button @click="handleDownload" variant="outline" size="sm">尝试下载</Button>
      </div>

      <!-- Prev/Next Buttons -->
      <button v-if="hasPrev" @click="prev"
        class="absolute left-4 top-1/2 -translate-y-1/2 p-2 rounded-full bg-background/50 hover:bg-background/80 transition-colors z-20">
        <ChevronLeft class="w-6 h-6" />
      </button>
      <button v-if="hasNext" @click="next"
        class="absolute right-4 top-1/2 -translate-y-1/2 p-2 rounded-full bg-background/50 hover:bg-background/80 transition-colors z-20">
        <ChevronRight class="w-6 h-6" />
      </button>
    </div>

    <!-- Playlist Sidebar -->
    <div v-if="playlist && playlist.length > 1 && showPlaylist"
      class="w-64 border-l border-border bg-card flex flex-col h-full transition-all duration-300">
      <div class="p-3 border-b border-border flex items-center justify-between font-medium text-sm">
        <span>播放列表 ({{ currentIndex + 1 }}/{{ playlist.length }})</span>
        <Button variant="ghost" size="icon" class="h-6 w-6" @click="showPlaylist = false">
          <X class="w-4 h-4" />
        </Button>
      </div>
      <div class="flex-1 overflow-y-auto p-2 space-y-1">
        <div v-for="(item, index) in playlist" :key="item.path"
          class="flex items-center gap-2 p-2 rounded-md cursor-pointer text-sm truncate transition-colors"
          :class="index === currentIndex ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'"
          @click="changeFile(index)" :ref="el => { if (index === currentIndex) activeItemRef = el as HTMLElement }">
          <component :is="item.type === 'video' ? FilmIcon : ImageIcon" class="w-4 h-4 shrink-0" />
          <span class="truncate">{{ item.filename }}</span>
        </div>
      </div>
    </div>

    <!-- Toggle Playlist Button (when hidden) -->
    <Button v-if="playlist && playlist.length > 1 && !showPlaylist" variant="outline" size="icon"
      class="absolute right-4 top-4 z-20 bg-background/50 hover:bg-background/80" @click="showPlaylist = true">
      <ListMusic class="w-4 h-4" />
    </Button>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted, nextTick, watch } from 'vue'
import { Button } from '@/components/ui/button'
import Player from 'xgplayer'
import 'xgplayer/dist/index.min.css'
import { FilmIcon, ImageIcon, ChevronLeft, ChevronRight, ListMusic, X } from 'lucide-vue-next'
import { useDesktopStore } from '@/stores/desktop'

const props = defineProps<{
  path: string
  sessionId: string
  windowId?: string
  playlist?: Array<{ path: string, filename: string, type: string }>
}>()

const desktopStore = useDesktopStore()
const error = ref(false)
const player = ref<Player | null>(null)
const activePath = ref(props.path)
const showPlaylist = ref(true)
const activeItemRef = ref<HTMLElement | null>(null)
let currentInitId = 0

const playerId = computed(() => `mse-${props.windowId || Math.random().toString(36).substr(2, 9)}`)

// Sync activePath with props.path when it changes externally
watch(() => props.path, (newPath) => {
  activePath.value = newPath
})

const currentIndex = computed(() => {
  if (!props.playlist) return -1
  return props.playlist.findIndex(item => item.path === activePath.value)
})

const hasPrev = computed(() => currentIndex.value > 0)
const hasNext = computed(() => props.playlist && currentIndex.value < props.playlist.length - 1)

const filename = computed(() => {
  return activePath.value.split('/').pop() || activePath.value
})

const ext = computed(() => {
  return filename.value.split('.').pop()?.toLowerCase() || ''
})

watch(filename, (newTitle) => {
  if (props.windowId) {
    const window = desktopStore.windows.find(w => w.id === props.windowId)
    if (window) {
      window.title = newTitle
    }
  }
})

const type = computed<'image' | 'video' | 'unknown'>(() => {
  const imageExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'ico']
  const videoExts = ['mp4', 'webm', 'ogg', 'mov', 'mkv', 'avi']

  if (imageExts.includes(ext.value)) return 'image'
  if (videoExts.includes(ext.value)) return 'video'
  return 'unknown'
})

const fileUrl = computed(() => {
  return `/api/files/read?sessionId=${props.sessionId}&path=${encodeURIComponent(activePath.value)}`
})

const handleError = () => {
  error.value = true
}

const handleDownload = () => {
  window.open(fileUrl.value + '&download=true', '_blank')
}

const changeFile = (index: number) => {
  if (props.playlist && props.playlist[index]) {
    activePath.value = props.playlist[index].path
  }
}

const prev = () => {
  if (hasPrev.value) {
    changeFile(currentIndex.value - 1)
  }
}

const next = () => {
  if (hasNext.value) {
    changeFile(currentIndex.value + 1)
  }
}

// Auto scroll to active item in playlist
watch(activeItemRef, (el) => {
  if (el) {
    el.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
  }
})

const initPlayer = () => {
  const initId = ++currentInitId

  if (player.value) {
    player.value.destroy()
    player.value = null
  }

  if (type.value === 'video') {
    nextTick(() => {
      // Check if another init call happened
      if (initId !== currentInitId) return;

      // Ensure container exists
      const container = document.getElementById(playerId.value)
      if (!container) return;

      try {
        player.value = new Player({
          id: playerId.value,
          url: fileUrl.value,
          height: '100%',
          width: '100%',
          autoplay: true,
          playbackRate: [0.5, 0.75, 1, 1.5, 2],
          download: true,
          keyShortcut: true,
          lang: 'zh-cn'
        })

        player.value.on('error', () => {
          handleError()
        })

        // Auto play next video when ended
        player.value.on('ended', () => {
          if (hasNext.value) {
            next()
          }
        })

      } catch (e) {
        console.error('Failed to init player', e)
        handleError()
      }
    })
  }
}

watch(() => activePath.value, () => {
  error.value = false
  initPlayer()
})

onMounted(() => {
  initPlayer()
})

onUnmounted(() => {
  if (player.value) {
    player.value.destroy()
    player.value = null
  }
})
</script>