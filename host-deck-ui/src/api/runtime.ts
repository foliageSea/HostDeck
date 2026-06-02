import { http } from '@/lib/http'

export interface RuntimeClientSummary {
  connectionId: string
  isClosed: boolean
  sessionCount: number
}

export interface RuntimeSessionSummary {
  sessionId: string
  connectionId: string
  type: 'shell' | 'sftp'
  hasShell: boolean
  clientClosed: boolean
}

export interface RuntimeSnapshot {
  totalClients: number
  totalSessions: number
  clients: RuntimeClientSummary[]
  sessions: RuntimeSessionSummary[]
}

export const runtimeApi = {
  getSessions: async () => {
    const response = await http.get<RuntimeSnapshot>('/api/runtime/sessions')
    return response.data
  },
}
