import { http } from '@/lib/http'

export type CronTaskTemplateType = 'backup' | 'cleanup' | 'health-check' | null
export type CronExecutionStatus = 'success' | 'failed'

export interface CronTask {
  id: number
  connectionId: string
  name: string
  schedule: string
  command: string
  enabled: boolean
  templateType: CronTaskTemplateType
  createdAt: number
  updatedAt: number
}

export interface CronTaskPayload {
  connectionId: string
  name: string
  schedule: string
  command: string
  enabled: boolean
  templateType?: CronTaskTemplateType
}

export interface CronExecutionHistory {
  id: number
  taskId: number
  connectionId: string
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
  async list(connectionId: string) {
    const response = await http.get<CronTask[]>('/api/cron-tasks', { params: { connectionId } })
    return response.data
  },
  async create(payload: CronTaskPayload) {
    const response = await http.post<CronTask>('/api/cron-tasks', payload)
    return response.data
  },
  async update(id: number, payload: CronTaskPayload) {
    const response = await http.put<CronTask>(`/api/cron-tasks/${id}`, payload)
    return response.data
  },
  async delete(id: number, connectionId: string) {
    const response = await http.delete<{ success: boolean }>(`/api/cron-tasks/${id}`, {
      params: { connectionId },
    })
    return response.data
  },
  async run(id: number, connectionId: string) {
    const response = await http.post<CronExecutionHistory>(`/api/cron-tasks/${id}/run`, null, {
      params: { connectionId },
    })
    return response.data
  },
  async history(id: number, connectionId: string) {
    const response = await http.get<CronExecutionHistory[]>(`/api/cron-tasks/${id}/history`, {
      params: { connectionId },
    })
    return response.data
  },
  async syncHistory(id: number, connectionId: string) {
    const response = await http.post<{ imported: number }>(`/api/cron-tasks/${id}/history/sync`, null, {
      params: { connectionId },
    })
    return response.data
  },
}
