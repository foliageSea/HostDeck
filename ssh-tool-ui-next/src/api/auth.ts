import { http } from '@/lib/http'

export interface ConnectParams {
  host: string
  port: number
  username: string
  password?: string
  privateKey?: string
}

export interface ConnectResponse {
  sessionId: string
  connectionId: string
}

export const authApi = {
  connect: async (data: ConnectParams) => {
    const response = await http.post<ConnectResponse>('/api/connect', data)
    return response.data
  },
}
