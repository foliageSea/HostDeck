import { http } from '@/lib/http'

export type CronTaskTemplateType = 'backup' | 'cleanup' | 'health-check' | null
export type CronExecutionStatus = 'success' | 'failed'

export interface CronTask {
  id: number
  serverId: number
  name: string
  schedule: string
  command: string
  enabled: boolean
  templateType: CronTaskTemplateType
  createdAt: number
  updatedAt: number
}

export interface CronTaskPayload {
  serverId: number
  name: string
  schedule: string
  command: string
  enabled: boolean
  templateType?: CronTaskTemplateType
}

export interface CronExecutionHistory {
  id: number
  taskId: number
  serverId: number
  triggerType: 'manual' | 'scheduled'
  startedAt: number
  finishedAt?: number | null
  durationMs?: number | null
  exitCode?: number | null
  status: CronExecutionStatus
  stdout?: string | null
  stderr?: string | null
}

export const cronTaskApi = {
  async list(serverId: number, connectionId: string) {
    const response = await http.get<CronTask[]>('/api/cron-tasks', { params: { serverId, connectionId } })
    return response.data
  },
  async create(payload: CronTaskPayload, connectionId: string) {
    const response = await http.post<CronTask>('/api/cron-tasks', payload, { params: { connectionId } })
    return response.data
  },
  async update(id: number, payload: CronTaskPayload, connectionId: string) {
    const response = await http.put<CronTask>(`/api/cron-tasks/${id}`, payload, { params: { connectionId } })
    return response.data
  },
  async delete(id: number, serverId: number, connectionId: string) {
    const response = await http.delete<{ success: boolean }>(`/api/cron-tasks/${id}`, {
      params: { serverId, connectionId },
    })
    return response.data
  },
  async run(id: number, serverId: number, connectionId: string) {
    const response = await http.post<CronExecutionHistory>(`/api/cron-tasks/${id}/run`, null, {
      params: { serverId, connectionId },
    })
    return response.data
  },
  async history(id: number, serverId: number, connectionId: string) {
    const response = await http.get<CronExecutionHistory[]>(`/api/cron-tasks/${id}/history`, {
      params: { serverId, connectionId },
    })
    return response.data
  },
  async syncHistory(id: number, serverId: number, connectionId: string) {
    const response = await http.post<{ imported: number }>(`/api/cron-tasks/${id}/history/sync`, null, {
      params: { serverId, connectionId },
    })
    return response.data
  },
}
