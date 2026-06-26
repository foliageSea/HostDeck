import { http } from '@/lib/http'

export interface ProcessInfo {
  pid: number
  user: string
  cpu: number
  memory: number
  rss: number
  stat: string
  start: string
  time: string
  command: string
}

export const processApi = {
  async list(connectionId: string) {
    const response = await http.get<ProcessInfo[]>('/api/processes', {
      params: { connectionId },
    })
    return response.data
  },

  async kill(connectionId: string, pid: number) {
    const response = await http.post<{ success: boolean }>(
      `/api/processes/${encodeURIComponent(pid)}/kill`,
      null,
      {
        params: { connectionId },
      },
    )
    return response.data
  },
}
