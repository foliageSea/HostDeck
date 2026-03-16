import { http } from '@/lib/http'

export interface FileItem {
  filename: string
  longname: string
  isDirectory: boolean
  size: number
  modifyTime?: string
}

export const fileApi = {
  createSession: async (connectionId: string) => {
    const response = await http.post<{ sessionId: string }>('/api/files/session', { connectionId })
    return response.data
  },
  
  listFiles: async (sessionId: string, path: string) => {
    const response = await http.get<FileItem[]>(`/api/files/list`, {
      params: { sessionId, path }
    })
    return response.data
  },

  uploadFile: async (sessionId: string, path: string, formData: FormData, onProgress?: (loaded: number, total: number) => void) => {
    const response = await http.post('/api/files/upload', formData, {
      params: { sessionId, path },
      headers: {
        'Content-Type': 'multipart/form-data'
      },
      onUploadProgress: (progressEvent) => {
        if (onProgress && progressEvent.total) {
          onProgress(progressEvent.loaded, progressEvent.total)
        }
      }
    })
    return response.data
  },

  batchDownload: async (sessionId: string, paths: string[]) => {
    const response = await http.post('/api/files/batch-download', { paths }, {
      params: { sessionId },
      responseType: 'blob'
    })
    return response.data
  },

  copy: async (sessionId: string, source: string, target: string) => {
    const response = await http.post('/api/files/copy', { source, target }, {
      params: { sessionId }
    })
    return response.data
  },

  rename: async (sessionId: string, oldPath: string, newPath: string) => {
    const response = await http.post('/api/files/rename', { oldPath, newPath }, {
      params: { sessionId }
    })
    return response.data
  },
  
  mkdir: async (sessionId: string, path: string) => {
    const response = await http.post('/api/files/mkdir', { path }, {
      params: { sessionId }
    })
    return response.data
  },

  deleteFile: async (sessionId: string, path: string) => {
    const response = await http.post('/api/files/delete', {}, {
      params: { sessionId, path }
    })
    return response.data
  },
  
  readFile: async (sessionId: string, path: string) => {
    const response = await http.get('/api/files/read', {
      params: { sessionId, path },
      responseType: 'text'
    })
    return response.data
  },

  download: async (sessionId: string, path: string) => {
    const response = await http.get('/api/files/read', {
      params: { sessionId, path, download: 'true' },
      responseType: 'blob'
    })
    return response.data
  }
}
