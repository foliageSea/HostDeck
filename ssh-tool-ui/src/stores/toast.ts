import { defineStore } from 'pinia'
import { ref } from 'vue'

export interface Toast {
  id: number
  message: string
  type: 'success' | 'error' | 'info' | 'warning'
}

export const useToastStore = defineStore('toast', () => {
  const toasts = ref<Toast[]>([])
  let nextId = 0

  const add = (message: string, type: Toast['type'] = 'info', duration = 3000) => {
    const id = nextId++
    toasts.value.push({ id, message, type })
    if (duration > 0) {
      setTimeout(() => {
        remove(id)
      }, duration)
    }
  }

  const remove = (id: number) => {
    const index = toasts.value.findIndex(t => t.id === id)
    if (index !== -1) {
      toasts.value.splice(index, 1)
    }
  }

  const success = (message: string) => add(message, 'success')
  const error = (message: string) => add(message, 'error')
  const info = (message: string) => add(message, 'info')
  const warning = (message: string) => add(message, 'warning')

  return { toasts, add, remove, success, error, info, warning }
})
