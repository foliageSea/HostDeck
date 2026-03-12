import { defineStore } from 'pinia'
import { ref, watch } from 'vue'

export interface SavedServer {
  id: string
  name: string
  host: string
  port: number
  username: string
}

export const useSshStore = defineStore('ssh', () => {
  const sessionId = ref<string | null>(null)
  const connectionId = ref<string | null>(null)
  const isConnected = ref(false)
  const host = ref('')
  const username = ref('')

  // Load saved servers from localStorage
  const savedServers = ref<SavedServer[]>([])
  
  try {
    const saved = localStorage.getItem('savedServers')
    if (saved) {
      savedServers.value = JSON.parse(saved)
    }
  } catch (e) {
    console.error('Failed to load saved servers:', e)
  }

  // Watch for changes and save to localStorage
  watch(savedServers, (newVal) => {
    localStorage.setItem('savedServers', JSON.stringify(newVal))
  }, { deep: true })

  function setSession(id: string, connId: string, h: string, u: string) {
    sessionId.value = id
    connectionId.value = connId
    host.value = h
    username.value = u
    isConnected.value = true
  }

  function clearSession() {
    sessionId.value = null
    connectionId.value = null
    isConnected.value = false
    host.value = ''
    username.value = ''
  }

  function addServer(server: Omit<SavedServer, 'id'>) {
    const id = typeof crypto !== 'undefined' && crypto.randomUUID 
      ? crypto.randomUUID() 
      : Date.now().toString(36) + Math.random().toString(36).substring(2)
      
    savedServers.value.push({ ...server, id })
  }

  function removeServer(id: string) {
    savedServers.value = savedServers.value.filter(s => s.id !== id)
  }
  
  function updateServer(id: string, server: Partial<SavedServer>) {
    const index = savedServers.value.findIndex(s => s.id === id)
    if (index !== -1) {
      savedServers.value[index] = { ...savedServers.value[index], ...server } as SavedServer
    }
  }

  return { 
    sessionId,
    connectionId,
    isConnected, 
    host, 
    username, 
    setSession, 
    clearSession,
    savedServers,
    addServer,
    removeServer,
    updateServer
  }
})
