import { http } from '@/lib/http'

export interface ConnectParams {
  host: string
  port: number
  username: string
  password?: string
  privateKey?: string
}

export interface ConnectResponse {
  connectionId: string
  host: string
  port: number
  username: string
  status: ConnectionStatus
  isConnected: boolean
  isRecoverable: boolean
  lastError: string | null
  updatedAt: string
}

export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'reconnecting' | 'failed'

export type ConnectionStatusResponse = ConnectResponse | null

export const authApi = {
  connect: async (data: ConnectParams) => {
    const response = await http.post<ConnectResponse>('/api/connect', data)
    return response.data
  },
  status: async () => {
    const response = await http.get<ConnectionStatusResponse>('/api/connect/status')
    return response.data
  },
  disconnect: async (connectionId?: string) => {
    const response = await http.delete<{ success: boolean }>('/api/connect', {
      params: connectionId ? { connectionId } : undefined,
    })
    return response.data
  },
}
