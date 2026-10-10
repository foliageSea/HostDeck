import { http } from '@/lib/http'

export interface AccessState {
  authenticated: boolean
  enabled: boolean
  passwordLoginEnabled: boolean
  totpLoginEnabled: boolean
  totpSource: 'none' | 'environment' | 'stored'
  totpIssuer: string
  totpAccount: string
  recoveryCodesRemaining: number
  principalType: string | null
}

export interface TotpSetup {
  secret: string
  provisioningUri: string
  recoveryCodes: string[]
}

export const accessApi = {
  getState: () => http.get<AccessState>('/api/access/state').then((response) => response.data),
  login: (credential: { password?: string; code?: string }) =>
    http
      .post<{ authenticated: boolean }>('/api/access/login', credential)
      .then((response) => response.data),
  beginTotpSetup: (currentCode?: string) =>
    http
      .post<TotpSetup>('/api/access/totp/setup', currentCode ? { currentCode } : {})
      .then((response) => response.data),
  confirmTotpSetup: (code: string) =>
    http.post<TotpSetup>('/api/access/totp/confirm', { code }).then((response) => response.data),
  disableTotp: (code: string) =>
    http
      .post<{ totpLoginEnabled: boolean }>('/api/access/totp/disable', { code })
      .then((response) => response.data),
  logout: () =>
    http.post<{ authenticated: boolean }>('/api/access/logout').then((response) => response.data),
}
