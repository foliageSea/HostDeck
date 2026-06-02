<script setup lang="ts">
import { computed, ref } from 'vue'
import { useSettingsStore } from '@/stores/settings'

const props = defineProps<{
  title?: string
  url: string
}>()

const settingsStore = useSettingsStore()
const isLoaded = ref(false)
const frameTitle = computed(() => props.title || props.url)
</script>

<template>
  <div
    class="relative h-full overflow-hidden"
    :class="settingsStore.isDark ? 'bg-[#020617]' : 'bg-[#f8fafc]'"
  >
    <div
      v-if="!isLoaded"
      class="absolute inset-0 z-10 flex items-center justify-center text-[0.92rem]"
      :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.72)]' : 'text-[rgba(51,65,85,0.72)]'"
    >
      正在打开 {{ frameTitle }} ...
    </div>

    <iframe
      class="h-full w-full border-0"
      :class="isLoaded ? 'opacity-100' : 'opacity-0'"
      :src="url"
      :title="frameTitle"
      allow="clipboard-read; clipboard-write"
      @load="isLoaded = true"
    />
  </div>
</template>
