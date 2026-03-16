import { http } from '@/lib/http'

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
  list: () => http.get<SavedServer[]>('/api/servers').then(res => res.data),
  create: (server: Omit<SavedServer, 'id'>) => http.post<SavedServer>('/api/servers', server).then(res => res.data),
  update: (id: number, server: Partial<SavedServer>) => http.put<{success: boolean}>(`/api/servers/${id}`, server).then(res => res.data),
  delete: (id: number) => http.delete<{success: boolean}>(`/api/servers/${id}`).then(res => res.data),
}
