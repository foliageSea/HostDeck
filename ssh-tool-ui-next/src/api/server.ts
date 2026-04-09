import { http } from '@/lib/http'
import type { AxiosResponse } from 'axios'

export interface SavedServer {
  id?: number
  name: string
  host: string
  port: number
  username: string
  password?: string
  privateKey?: string
  createdAt?: number
}

export const serverApi = {
  list: () => http.get<SavedServer[]>('/api/servers').then((res: AxiosResponse<SavedServer[]>) => res.data),
  create: (server: Omit<SavedServer, 'id'>) =>
    http.post<SavedServer>('/api/servers', server).then((res: AxiosResponse<SavedServer>) => res.data),
  update: (id: number, server: Partial<SavedServer>) =>
    http.put<{ success: boolean }>(`/api/servers/${id}`, server).then((res: AxiosResponse<{ success: boolean }>) => res.data),
  delete: (id: number) =>
    http.delete<{ success: boolean }>(`/api/servers/${id}`).then((res: AxiosResponse<{ success: boolean }>) => res.data),
}
