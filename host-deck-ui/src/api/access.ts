import { http } from '@/lib/http'

export interface AccessState {
  authenticated: boolean
  enabled: boolean
  passwordLoginEnabled: boolean
  principalType: string | null
}

export const accessApi = {
  getState: () => http.get<AccessState>('/api/access/state').then((response) => response.data),
  login: (password: string) =>
    http.post<{ authenticated: boolean }>('/api/access/login', { password }).then((response) => response.data),
  logout: () =>
    http.post<{ authenticated: boolean }>('/api/access/logout').then((response) => response.data),
}
