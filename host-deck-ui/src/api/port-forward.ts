import { http } from '@/lib/http'

export type PortForwardStatus = 'running' | 'stopped' | 'error'

export interface PortForwardRule {
  id: number
  name: string
  enabled: boolean
  bindHost: string
  localPort: number
  remoteHost: string
  remotePort: number
  createdAt?: number | null
  updatedAt?: number | null
  status: PortForwardStatus
  error?: string | null
  connectionId?: string | null
  startedAt?: number | null
  activeConnections?: number
}

export interface PortForwardPayload {
  name: string
  enabled: boolean
  bindHost: string
  localPort: number
  remoteHost: string
  remotePort: number
  connectionId?: string | null
}

export const portForwardApi = {
  create: async (payload: PortForwardPayload) => {
    const response = await http.post<PortForwardRule>('/api/port-forwards', payload)
    return response.data
  },
  delete: async (id: number) => {
    const response = await http.delete<{ success: boolean }>(`/api/port-forwards/${id}`)
    return response.data
  },
  list: async () => {
    const response = await http.get<PortForwardRule[]>('/api/port-forwards')
    return response.data
  },
  start: async (id: number, connectionId: string) => {
    const response = await http.post<PortForwardRule>(`/api/port-forwards/${id}/start`, { connectionId })
    return response.data
  },
  stop: async (id: number) => {
    const response = await http.post<PortForwardRule>(`/api/port-forwards/${id}/stop`)
    return response.data
  },
  update: async (id: number, payload: PortForwardPayload) => {
    const response = await http.put<PortForwardRule>(`/api/port-forwards/${id}`, payload)
    return response.data
  },
}
