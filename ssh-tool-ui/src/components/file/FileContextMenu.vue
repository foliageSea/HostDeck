<template>
  <div v-if="visible" 
    :style="{ top: y + 'px', left: x + 'px' }"
    class="fixed z-50 bg-white/90 dark:bg-[#2d2d2d]/90 backdrop-blur-md shadow-xl rounded-lg border border-gray-200/50 dark:border-black/50 py-1.5 min-w-[200px] text-gray-800 dark:text-gray-200 select-none"
    @click.stop
  >
    <div v-for="(item, index) in items" :key="index">
      <div v-if="item.separator" class="border-t border-gray-200 dark:border-gray-600 my-1 mx-3"></div>
      <div v-else
        @click="handleClick(item)"
        class="px-3 py-1 mx-1 rounded-[4px] hover:bg-[#007AFF] hover:text-white cursor-default text-[13px] flex items-center gap-3 transition-colors group"
      >
        <component :is="item.icon" class="w-4 h-4 text-gray-500 dark:text-gray-400 group-hover:text-white" />
        <span class="flex-1">{{ item.label }}</span>
      </div>
    </div>
  </div>
  <!-- Overlay to close menu on click outside -->
  <div v-if="visible" class="fixed inset-0 z-40" @click="$emit('close')"></div>
</template>

<script setup lang="ts">
import { type Component } from 'vue'

export interface MenuItem {
  label: string
  icon?: Component
  action?: () => void
  separator?: boolean
}

defineProps<{
  visible: boolean
  x: number
  y: number
  items: MenuItem[]
}>()

const emit = defineEmits(['close'])

const handleClick = (item: MenuItem) => {
  if (item.action) {
    item.action()
  }
  emit('close')
}
</script>
