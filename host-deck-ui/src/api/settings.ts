import { http } from '@/lib/http'
import type { WallpaperSettings, WallpaperTarget } from '@/lib/wallpapers'

export interface UiSettingsPayload {
  desktopWallpaper?: WallpaperSettings
  loginWallpaper?: WallpaperSettings
}

export interface UploadedWallpaper {
  customType: 'image' | 'video'
  url: string
}

export interface ServiceVersion {
  version: string
}

export interface TlsCertificateInfo {
  subject: string
  hosts: string[]
  notBefore: string
  notAfter: string
  fingerprint256: string
}

export interface TlsConfig {
  enabled: boolean
  source: 'selfSigned' | 'imported'
  hosts: string[]
  certificate: TlsCertificateInfo | null
}

export interface TlsState {
  saved: TlsConfig
  active: TlsConfig
  restartRequired: boolean
  managedExternally: boolean
}

export interface TlsSettingsPayload {
  enabled: boolean
  source: TlsConfig['source']
  hosts?: string[]
  certificatePem?: string
  privateKeyPem?: string
  regenerate?: boolean
}

export interface BackendPortInfo {
  id: string
  type: 'server' | 'port-forward' | 'secure-browser' | 'docker' | 'ide'
  name: string
  host: string
  port: number
  scheme?: 'http' | 'https'
  purpose: string
  status: 'running' | 'error'
  target?: string
  connectionId?: string
  activeConnections?: number
  startedAt?: number
  error?: string
}

export interface BackendPortsPayload {
  items: BackendPortInfo[]
}

export const settingsApi = {
  getTlsSettings: async () => (await http.get<TlsState>('/api/settings/tls')).data,

  saveTlsSettings: async (payload: TlsSettingsPayload) =>
    (await http.put<TlsState>('/api/settings/tls', payload)).data,

  downloadTlsCertificate: async () =>
    (await http.get<Blob>('/api/settings/tls/certificate', { responseType: 'blob' })).data,

  getServiceVersion: async () => {
    const response = await http.get<ServiceVersion>('/api/settings/version')
    return response.data
  },

  getBackendPorts: async () => {
    const response = await http.get<BackendPortsPayload>('/api/settings/ports')
    return response.data
  },

  getUiSettings: async () => {
    const response = await http.get<UiSettingsPayload>('/api/settings/ui')
    return response.data
  },

  saveUiSettings: async (payload: UiSettingsPayload) => {
    const response = await http.put<UiSettingsPayload>('/api/settings/ui', payload)
    return response.data
  },

  uploadWallpaper: async (target: WallpaperTarget, file: File) => {
    const formData = new FormData()
    formData.append('file', file)
    const response = await http.post<UploadedWallpaper>('/api/settings/ui/wallpapers', formData, {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
      params: { target },
    })
    return response.data
  },

  exportLogs: async () => {
    const response = await http.get<Blob>('/api/settings/logs/export', {
      responseType: 'blob',
    })
    return response.data
  },
}
