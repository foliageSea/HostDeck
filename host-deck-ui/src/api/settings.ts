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

export interface BackendPortInfo {
  id: string
  type: 'server' | 'port-forward' | 'secure-browser' | 'docker'
  name: string
  host: string
  port: number
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
