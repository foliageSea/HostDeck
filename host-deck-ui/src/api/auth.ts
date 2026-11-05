import { http } from '@/lib/http'

export interface ConnectParams {
  serverId?: number
  host: string
  port: number
  username: string
  password?: string
  privateKey?: string
}

export interface ConnectResponse {
  connectionId: string
}

export interface ConnectOptions {
  requestId: string
  signal: AbortSignal
}

export const authApi = {
  connect: async (data: ConnectParams, options?: ConnectOptions) => {
    const response = options
      ? await http.post<ConnectResponse>(
          '/api/connect',
          { ...data, requestId: options.requestId },
          { signal: options.signal },
        )
      : await http.post<ConnectResponse>('/api/connect', data)
    return response.data
  },
  cancelConnect: async (requestId: string) => {
    const response = await http.delete<{ success: boolean }>('/api/connect/pending', {
      params: { requestId },
    })
    return response.data
  },
  testConnect: async (data: ConnectParams) => {
    const response = await http.post<{ success: boolean }>('/api/connect/test', data)
    return response.data
  },
  disconnect: async (connectionId: string) => {
    const response = await http.delete<{ success: boolean }>('/api/connect', {
      params: { connectionId },
    })
    return response.data
  },
}
