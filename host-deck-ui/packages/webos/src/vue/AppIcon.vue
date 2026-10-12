<script setup lang="ts">
import { computed } from 'vue'
import { useDesktopContext } from './context'

const props = withDefaults(defineProps<{ name: string; size?: number; themed?: boolean }>(), {
  size: 18,
})
const context = useDesktopContext()
const icon = computed(() => context.resolveIcon?.(props.name) ?? props.name)
</script>

<template>
  <img
    v-if="typeof icon === 'string'"
    :src="icon"
    :width="size"
    :height="size"
    alt=""
    aria-hidden="true"
    class="block flex-none object-contain"
    draggable="false"
  />
  <component
    v-else
    :is="icon"
    :size="size"
    :style="{ width: `${size}px`, height: `${size}px` }"
    aria-hidden="true"
  />
</template>
