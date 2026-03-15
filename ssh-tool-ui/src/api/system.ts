import { http } from '@/lib/http'

export interface MonitorResponse {
  cpu: string 
  cpuUsage?: number
  ram: {
    total: number
    used: number
    free: number
  }
  disk: string
  network?: {
    uploadSpeed: number
    downloadSpeed: number
  }
}

export const systemApi = {
  getMonitorStatus: async (sessionId: string) => {
    const response = await http.get<MonitorResponse>('/api/monitor', {
      params: { sessionId }
    })
    return response.data
  }
}
