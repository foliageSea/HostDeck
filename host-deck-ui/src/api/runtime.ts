import { http } from '@/lib/http'

export interface RuntimeClientSummary {
  connectionId: string
  isClosed: boolean
  sessionCount: number
}

export type RuntimeSessionPurpose =
  | 'terminal'
  | 'fileManagement'
  | 'fileTask'
  | 'docker'
  | 'dockerCompose'
  | 'containerShell'
  | 'systemMonitor'
  | 'agent'
  | 'cronTask'
  | 'processManagement'

export interface RuntimeSessionSummary {
  sessionId: string
  connectionId: string
  type: 'shell' | 'sftp'
  purposes: RuntimeSessionPurpose[]
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
