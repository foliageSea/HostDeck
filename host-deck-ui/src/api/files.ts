import type { AxiosProgressEvent } from 'axios'
import { http } from '@/lib/http'

export interface FileItem {
  filename: string
  longname: string
  isDirectory: boolean
  size: number
  modifyTime?: string
}

export interface DirectorySizeResult {
  size: number
}

export const filesApi = {
  createSession: async (connectionId: string) => {
    const response = await http.post<{ sessionId: string }>('/api/files/session', { connectionId })
    return response.data
  },

  deleteSession: async (sessionId: string) => {
    const response = await http.delete('/api/files/session', {
      params: { sessionId },
    })
    return response.data
  },

  list: async (connectionId: string, path: string) => {
    const response = await http.get<FileItem[]>('/api/files/list', {
      params: { connectionId, path },
    })
    return response.data
  },

  directorySize: async (connectionId: string, path: string) => {
    const response = await http.get<DirectorySizeResult>('/api/files/directory-size', {
      params: { connectionId, path },
    })
    return response.data
  },

  mkdir: async (connectionId: string, path: string) => {
    const response = await http.post(
      '/api/files/mkdir',
      { path },
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  chmod: async (connectionId: string, path: string, mode: string, recursive = false) => {
    const response = await http.post(
      '/api/files/chmod',
      { mode, path, recursive },
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  rename: async (connectionId: string, oldPath: string, newPath: string) => {
    const response = await http.post(
      '/api/files/rename',
      { newPath, oldPath },
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  copy: async (connectionId: string, source: string, target: string) => {
    const response = await http.post(
      '/api/files/copy',
      { source, target },
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  extract: async (connectionId: string, archivePath: string, targetPath: string) => {
    const response = await http.post(
      '/api/files/extract',
      { archivePath, targetPath },
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  delete: async (connectionId: string, path: string) => {
    const response = await http.post(
      '/api/files/delete',
      {},
      {
        params: { connectionId, path },
      },
    )
    return response.data
  },

  upload: async (
    connectionId: string,
    path: string,
    formData: FormData,
    onUploadProgress?: (event: AxiosProgressEvent) => void,
    signal?: AbortSignal,
  ) => {
    const response = await http.post('/api/files/upload', formData, {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
      onUploadProgress,
      params: { connectionId, path },
      signal,
    })
    return response.data
  },

  writeFile: async (connectionId: string, path: string, content: string) => {
    const response = await http.post('/api/files/write', content, {
      headers: {
        'Content-Type': 'text/plain',
      },
      params: { connectionId, path },
    })
    return response.data
  },

  readFile: async (connectionId: string, path: string) => {
    const response = await http.get<string>('/api/files/read', {
      params: { connectionId, path },
      responseType: 'text',
    })
    return response.data
  },

  download: async (
    connectionId: string,
    path: string,
    onDownloadProgress?: (event: AxiosProgressEvent) => void,
    signal?: AbortSignal,
  ) => {
    const response = await http.get<Blob>('/api/files/read', {
      onDownloadProgress,
      params: { connectionId, download: 'true', path },
      responseType: 'blob',
      signal,
    })
    return response.data
  },

  batchDownload: async (
    connectionId: string,
    paths: string[],
    onDownloadProgress?: (event: AxiosProgressEvent) => void,
    signal?: AbortSignal,
  ) => {
    const response = await http.post<Blob>(
      '/api/files/batch-download',
      { paths },
      {
        onDownloadProgress,
        params: { connectionId },
        responseType: 'blob',
        signal,
      },
    )
    return response.data
  },
}
