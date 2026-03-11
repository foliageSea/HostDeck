<template>
  <div class="fixed top-4 right-4 z-50 flex flex-col gap-2 pointer-events-none">
    <transition-group name="toast">
      <div v-for="toast in toasts" :key="toast.id" 
        :class="['p-4 rounded shadow-lg text-white min-w-[300px] pointer-events-auto flex items-center justify-between', toastClass(toast.type)]">
        <span>{{ toast.message }}</span>
        <button @click="remove(toast.id)" class="ml-4 text-white hover:text-gray-200">×</button>
      </div>
    </transition-group>
  </div>
</template>

<script setup lang="ts">
import { useToastStore } from '@/stores/toast'
import { storeToRefs } from 'pinia'

const store = useToastStore()
const { toasts } = storeToRefs(store)

const remove = (id: number) => {
  store.remove(id)
}

const toastClass = (type: 'success' | 'error' | 'info' | 'warning') => {
  switch (type) {
    case 'success': return 'bg-green-500'
    case 'error': return 'bg-red-500'
    case 'warning': return 'bg-yellow-500'
    default: return 'bg-blue-500'
  }
}
</script>

<style scoped>
.toast-enter-active,
.toast-leave-active {
  transition: all 0.3s ease;
}
.toast-enter-from,
.toast-leave-to {
  opacity: 0;
  transform: translateX(30px);
}
</style>
