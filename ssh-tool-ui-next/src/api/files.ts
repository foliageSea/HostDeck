import type { AxiosProgressEvent } from 'axios'
import { http } from '@/lib/http'

export interface FileItem {
  filename: string
  longname: string
  isDirectory: boolean
  size: number
  modifyTime?: string
}

export const filesApi = {
  createSession: async (connectionId: string) => {
    const response = await http.post<{ sessionId: string }>('/api/files/session', { connectionId })
    return response.data
  },

  list: async (sessionId: string, path: string) => {
    const response = await http.get<FileItem[]>('/api/files/list', {
      params: { path, sessionId },
    })
    return response.data
  },

  mkdir: async (sessionId: string, path: string) => {
    const response = await http.post('/api/files/mkdir', { path }, {
      params: { sessionId },
    })
    return response.data
  },

  rename: async (sessionId: string, oldPath: string, newPath: string) => {
    const response = await http.post('/api/files/rename', { newPath, oldPath }, {
      params: { sessionId },
    })
    return response.data
  },

  delete: async (sessionId: string, path: string) => {
    const response = await http.post('/api/files/delete', {}, {
      params: { path, sessionId },
    })
    return response.data
  },

  upload: async (
    sessionId: string,
    path: string,
    formData: FormData,
    onUploadProgress?: (event: AxiosProgressEvent) => void,
  ) => {
    const response = await http.post('/api/files/upload', formData, {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
      onUploadProgress,
      params: { path, sessionId },
    })
    return response.data
  },

  writeFile: async (sessionId: string, path: string, content: string) => {
    const response = await http.post('/api/files/write', content, {
      headers: {
        'Content-Type': 'text/plain',
      },
      params: { path, sessionId },
    })
    return response.data
  },

  readFile: async (sessionId: string, path: string) => {
    const response = await http.get<string>('/api/files/read', {
      params: { path, sessionId },
      responseType: 'text',
    })
    return response.data
  },

  download: async (sessionId: string, path: string) => {
    const response = await http.get<Blob>('/api/files/read', {
      params: { download: 'true', path, sessionId },
      responseType: 'blob',
    })
    return response.data
  },

  batchDownload: async (sessionId: string, paths: string[]) => {
    const response = await http.post<Blob>('/api/files/batch-download', { paths }, {
      params: { sessionId },
      responseType: 'blob',
    })
    return response.data
  },
}
