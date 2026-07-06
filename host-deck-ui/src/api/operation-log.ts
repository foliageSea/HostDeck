import { http } from '@/lib/http'

export type OperationLogStatus = 'success' | 'failed'

export interface OperationLogItem {
  id: number
  category: string
  action: string
  target?: string | null
  detail?: Record<string, unknown> | null
  status: OperationLogStatus
  errorMessage?: string | null
  connectionId?: string | null
  createdAt: number
}

export interface OperationLogListParams {
  category?: string
  limit?: number
  offset?: number
  status?: OperationLogStatus | ''
}

export const operationLogApi = {
  async clear() {
    const response = await http.delete<{ success: boolean }>('/api/operation-logs')
    return response.data
  },

  async list(params: OperationLogListParams = {}) {
    const response = await http.get<OperationLogItem[]>('/api/operation-logs', { params })
    return response.data
  },
}
