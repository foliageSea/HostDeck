import type { AxiosResponse } from 'axios'

import { http } from '@/lib/http'

export interface MonitorResponse {
  timestamp: number
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
  getMonitorHistory: (connectionId: string, limit = 200) =>
    http
      .get<MonitorResponse[]>('/api/system/monitor/history', {
        params: {
          connectionId,
          limit,
        },
      })
      .then((res: AxiosResponse<MonitorResponse[]>) => res.data),
}
