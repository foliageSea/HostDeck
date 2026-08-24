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

export const settingsApi = {
  getServiceVersion: async () => {
    const response = await http.get<ServiceVersion>('/api/settings/version')
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
