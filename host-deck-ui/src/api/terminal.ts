import { http } from '@/lib/http'

export interface CreateTerminalSessionParams {
  connectionId: string
  cols: number
  rows: number
}

export interface TerminalSessionResponse {
  sessionId: string
}

export interface TerminalSnippet {
  id: number
  name: string
  command: string
  createdAt: number
  updatedAt: number
}

export interface TerminalSnippetPayload {
  name: string
  command: string
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

  listSnippets: async () => {
    const response = await http.get<TerminalSnippet[]>('/api/terminal/snippets')
    return response.data
  },

  createSnippet: async (payload: TerminalSnippetPayload) => {
    const response = await http.post<TerminalSnippet>('/api/terminal/snippets', payload)
    return response.data
  },

  updateSnippet: async (id: number, payload: TerminalSnippetPayload) => {
    const response = await http.put<TerminalSnippet>(`/api/terminal/snippets/${id}`, payload)
    return response.data
  },

  deleteSnippet: async (id: number) => {
    const response = await http.delete<{ success: boolean }>(`/api/terminal/snippets/${id}`)
    return response.data
  },
}
