import { http } from '@/lib/http'

export interface SecureBrowserTunnel {
  id: string
  connectionId: string
  bindHost: string
  bindPort: number
  startedAt: number
  status: 'running'
}

export interface CreateSecureBrowserTunnelPayload {
  connectionId: string
}

export const secureBrowserApi = {
  create: async (payload: CreateSecureBrowserTunnelPayload) => {
    const response = await http.post<SecureBrowserTunnel>('/api/secure-browser-tunnels', payload)
    return response.data
  },
  list: async () => {
    const response = await http.get<SecureBrowserTunnel[]>('/api/secure-browser-tunnels')
    return response.data
  },
  stop: async (id: string) => {
    const response = await http.delete<{ success: boolean }>(`/api/secure-browser-tunnels/${id}`)
    return response.data
  },
}
