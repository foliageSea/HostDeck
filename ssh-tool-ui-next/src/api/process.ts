import { http } from '@/lib/http'

export type ProcessSortBy = 'cpu' | 'memory' | 'pid' | 'user' | 'command'
export type ProcessSortOrder = 'asc' | 'desc'
export type ProcessSignal = 'TERM' | 'KILL' | 'HUP'

export interface ProcessInfo {
  pid: number
  ppid: number
  user: string
  cpuPercent: number
  memoryPercent: number
  state: string
  startTime: string
  elapsed: string
  command: string
  commandLine: string
}

export interface ProcessDetail extends ProcessInfo {
  pgid: number
  sid: number
  tty: string
}

export interface ProcessTreeNode extends ProcessInfo {
  children: ProcessTreeNode[]
}

export interface StartProcessPayload {
  command: string
  connectionId: string
  environment?: Record<string, string>
  workingDirectory?: string
}

export interface StartProcessResult {
  pid: number
  logPath: string
  startedCommand: string
}

export const processApi = {
  getDetail: async (connectionId: string, pid: number) => {
    const response = await http.get<ProcessDetail>(`/api/processes/${pid}`, {
      params: { connectionId },
    })
    return response.data
  },

  getTree: async (connectionId: string, params?: { keyword?: string; user?: string }) => {
    const response = await http.get<ProcessTreeNode[]>('/api/processes/tree', {
      params: {
        connectionId,
        ...params,
      },
    })
    return response.data
  },

  list: async (connectionId: string, params?: {
    keyword?: string
    limit?: number
    sortBy?: ProcessSortBy
    sortOrder?: ProcessSortOrder
    user?: string
  }) => {
    const response = await http.get<ProcessInfo[]>('/api/processes', {
      params: {
        connectionId,
        ...params,
      },
    })
    return response.data
  },

  sendSignal: async (connectionId: string, pid: number, signal: ProcessSignal) => {
    const response = await http.post<{ success: boolean }>(`/api/processes/${pid}/signal`, {
      connectionId,
      signal,
    })
    return response.data
  },

  start: async (payload: StartProcessPayload) => {
    const response = await http.post<StartProcessResult>('/api/processes/start', payload)
    return response.data
  },
}
