<template>
  <div v-if="visible" 
    :style="{ top: y + 'px', left: x + 'px' }"
    class="fixed z-50 bg-white dark:bg-gray-800 shadow-lg rounded-lg border border-gray-200 dark:border-gray-700 py-1 min-w-[180px] text-gray-700 dark:text-gray-200"
    @click.stop
  >
    <div v-for="(item, index) in items" :key="index">
      <div v-if="item.separator" class="border-t border-gray-200 dark:border-gray-700 my-1"></div>
      <div v-else
        @click="handleClick(item)"
        class="px-4 py-2 hover:bg-blue-50 dark:hover:bg-blue-900/30 hover:text-blue-600 dark:hover:text-blue-400 cursor-pointer text-sm flex items-center gap-3 transition-colors"
      >
        <component :is="item.icon" class="w-4 h-4" />
        {{ item.label }}
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
