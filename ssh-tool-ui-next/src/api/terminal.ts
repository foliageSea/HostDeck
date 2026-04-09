import { http } from '@/lib/http'

export interface CreateTerminalSessionParams {
  connectionId: string
  cols: number
  rows: number
}

export interface TerminalSessionResponse {
  sessionId: string
}

export const terminalApi = {
  createSession: async (data: CreateTerminalSessionParams) => {
    const response = await http.post<TerminalSessionResponse>('/api/terminal/session', data)
    return response.data
  },

  deleteSession: async (sessionId: string) => {
    const response = await http.delete('/api/terminal/session', {
      params: { sessionId },
    })
    return response.data
  },
}
