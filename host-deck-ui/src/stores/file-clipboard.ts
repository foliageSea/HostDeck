import { computed, ref } from 'vue'
import { defineStore } from 'pinia'

export type FileClipboardOperation = 'copy' | 'move'

export interface FileClipboardEntry {
  filename: string
  isDirectory: boolean
  path: string
}

interface FileClipboardPayload {
  connectionKey: string
  entries: FileClipboardEntry[]
  operation: FileClipboardOperation
  sourcePath: string
}

interface FileClipboardRefreshEvent {
  id: number
  path: string
  sourceWindowId?: string
}

export const useFileClipboardStore = defineStore('fileClipboard', () => {
  const payload = ref<FileClipboardPayload | null>(null)
  const refreshEvent = ref<FileClipboardRefreshEvent | null>(null)
  const refreshEventId = ref(0)

  const hasPayload = computed(() => payload.value !== null)

  function setPayload(nextPayload: FileClipboardPayload) {
    payload.value = nextPayload
  }

  function clearPayload() {
    payload.value = null
  }

  function emitRefresh(path: string, sourceWindowId?: string) {
    refreshEventId.value += 1
    refreshEvent.value = {
      id: refreshEventId.value,
      path,
      sourceWindowId,
    }
  }

  return {
    clearPayload,
    emitRefresh,
    hasPayload,
    payload,
    refreshEvent,
    setPayload,
  }
})
