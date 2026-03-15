import { http } from '@/lib/http'

export interface CreateSessionParams {
  connectionId: string
  cols: number
  rows: number
}

export interface SessionResponse {
  sessionId: string
}

export const terminalApi = {
  createSession: async (data: CreateSessionParams) => {
    const response = await http.post<SessionResponse>('/api/terminal/session', data)
    return response.data
  },
  
  getSession: async (sessionId: string) => {
    const response = await http.get<SessionResponse>('/api/terminal/session', {
      params: { sessionId }
    })
    return response.data
  },

  resizeSession: async (sessionId: string, cols: number, rows: number) => {
    const response = await http.post('/api/terminal/resize', {
      sessionId,
      cols,
      rows
    })
    return response.data
  },

  deleteSession: async (sessionId: string) => {
    const response = await http.delete('/api/terminal/session', {
      params: { sessionId }
    })
    return response.data
  }
}
