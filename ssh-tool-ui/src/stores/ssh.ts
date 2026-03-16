import { defineStore } from 'pinia'
import { ref } from 'vue'
import { serverApi, type SavedServer } from '@/api/server'

export { type SavedServer }

export const useSshStore = defineStore('ssh', () => {
  const sessionId = ref<string | null>(null)
  const connectionId = ref<string | null>(null)
  const isConnected = ref(false)
  const host = ref('')
  const username = ref('')

  const savedServers = ref<SavedServer[]>([])

  async function fetchServers() {
    try {
      const servers = await serverApi.list()
      savedServers.value = servers
    } catch (e) {
      console.error('Failed to fetch servers:', e)
    }
  }

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

  async function addServer(server: Omit<SavedServer, 'id'>) {
    try {
      const newServer = await serverApi.create(server)
      savedServers.value.unshift(newServer)
    } catch (e) {
      console.error('Failed to add server:', e)
      throw e
    }
  }

  async function removeServer(id: number) {
    try {
      await serverApi.delete(id)
      savedServers.value = savedServers.value.filter(s => s.id !== id)
    } catch (e) {
      console.error('Failed to remove server:', e)
      throw e
    }
  }
  
  async function updateServer(id: number, server: Partial<SavedServer>) {
    try {
      await serverApi.update(id, server)
      const index = savedServers.value.findIndex(s => s.id === id)
      if (index !== -1) {
        savedServers.value[index] = { ...savedServers.value[index], ...server }
      }
    } catch (e) {
      console.error('Failed to update server:', e)
      throw e
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
    fetchServers,
    addServer,
    removeServer,
    updateServer
  }
})
