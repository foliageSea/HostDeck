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
}

export const authApi = {
  connect: async (data: ConnectParams) => {
    const response = await http.post<ConnectResponse>('/api/connect', data)
    return response.data
  },
  disconnect: async (connectionId: string) => {
    const response = await http.delete<{ success: boolean }>('/api/connect', {
      params: { connectionId },
    })
    return response.data
  },
}
