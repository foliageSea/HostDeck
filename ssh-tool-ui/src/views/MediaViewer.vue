<template>
  <div class="h-full w-full bg-background flex flex-col items-center justify-center relative overflow-hidden">
    <template v-if="type === 'image'">
      <img :src="fileUrl" class="max-w-full max-h-full object-contain select-none" :alt="filename"
        @error="handleError" />
    </template>
    <template v-else-if="type === 'video'">
      <div id="mse" class="w-full h-full"></div>
    </template>

    <div v-if="error"
      class="text-destructive flex flex-col items-center gap-2 p-4 text-center z-10 bg-background/80 rounded-lg absolute">
      <p>无法加载媒体文件</p>
      <Button @click="handleDownload" variant="outline" size="sm">尝试下载</Button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted, nextTick, watch } from 'vue'
import { Button } from '@/components/ui/button'
import Player from 'xgplayer'
import 'xgplayer/dist/index.min.css'

const props = defineProps<{
  path: string
  sessionId: string
  windowId?: string
}>()

const error = ref(false)
const player = ref<Player | null>(null)

const filename = computed(() => {
  return props.path.split('/').pop() || props.path
})

const ext = computed(() => {
  return filename.value.split('.').pop()?.toLowerCase() || ''
})

const type = computed<'image' | 'video' | 'unknown'>(() => {
  const imageExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'ico']
  const videoExts = ['mp4', 'webm', 'ogg', 'mov', 'mkv', 'avi']

  if (imageExts.includes(ext.value)) return 'image'
  if (videoExts.includes(ext.value)) return 'video'
  return 'unknown'
})

const fileUrl = computed(() => {
  return `/api/files/read?sessionId=${props.sessionId}&path=${encodeURIComponent(props.path)}`
})

const handleError = () => {
  error.value = true
}

const handleDownload = () => {
  window.open(fileUrl.value + '&download=true', '_blank')
}

const initPlayer = () => {
  if (type.value === 'video') {
    nextTick(() => {
      if (player.value) {
        player.value.destroy()
        player.value = null
      }

      try {
        player.value = new Player({
          id: 'mse',
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
      } catch (e) {
        console.error('Failed to init player', e)
        handleError()
      }
    })
  }
}

watch(() => props.path, () => {
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
