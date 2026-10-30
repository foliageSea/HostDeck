import { http, handleAccessUnauthorized } from '@/lib/http'

/** code-server 离线包支持的 Linux 架构。 */
export type CodeServerArch = 'amd64' | 'arm64'

/** 与后端 IdeSessionState 对齐的会话状态。 */
export type CodeServerSessionState =
  | 'installing'
  | 'starting'
  | 'running'
  | 'stopping'
  | 'stopped'
  | 'error'

/** GET /api/code-server/packages 返回的离线包元数据。 */
export interface CodeServerPackage {
  id: string
  version: string
  arch: string
  path?: string | null
  size: number
  sha256: string
  createdAt: string
}

/** 目标机安装前检查结果。 */
export interface CodeServerPreflight {
  arch: string
  libc: string | null
  diskFreeBytes: number | null
  installedVersion: string | null
  installRoot?: string | null
  dataRoot?: string | null
  issues: string[]
  supported: boolean
}

/** 当前目标机上的 IDE 会话快照。 */
export interface CodeServerSession {
  id: string
  state: CodeServerSessionState
  error: string | null
  version: string | null
  progress: number | null
  installStage?: 'transferring' | 'verifying' | 'extracting' | 'finalizing' | null
  startedAt: string | null
  /** 同源相对路径，例如 /ide/<sessionId>/，由后端代理提供。 */
  url?: string | null
}

export interface CodeServerTargetStatus {
  connectionId?: string
  preflight: CodeServerPreflight | null
  /** 预检命令自身失败时的错误信息（此时 preflight 为 null）。 */
  preflightError?: string | null
  session: CodeServerSession | null
  packages?: CodeServerPackage[]
}

export interface ScanPackagesResult {
  packages: CodeServerPackage[]
}

export interface UploadPackageOptions {
  version: string
  arch: CodeServerArch
  onProgress?: (loaded: number, total: number) => void
}

interface UnifiedResult<T> {
  code?: number
  message?: string
  data?: T
}

function parseResult<T>(text: string): UnifiedResult<T> {
  try {
    const parsed = JSON.parse(text) as unknown
    if (parsed && typeof parsed === 'object') {
      return parsed as UnifiedResult<T>
    }
  } catch {
    // 非 JSON 响应交给调用方按 HTTP 状态处理。
  }
  return {}
}

export const codeServerApi = {
  listPackages: async () => {
    const response = await http.get<CodeServerPackage[]>('/api/code-server/packages')
    return response.data
  },

  deletePackage: async (id: string) => {
    const response = await http.delete<{ success: boolean }>(
      `/api/code-server/packages/${encodeURIComponent(id)}`,
    )
    return response.data
  },

  scanPackages: async () => {
    const response = await http.post<ScanPackagesResult>('/api/code-server/packages/scan')
    return response.data
  },

  status: async (connectionId: string) => {
    const response = await http.get<CodeServerTargetStatus>(
      `/api/code-server/targets/${encodeURIComponent(connectionId)}/status`,
    )
    return response.data
  },

  install: async (connectionId: string, packageId: string) => {
    const response = await http.post<CodeServerSession>(
      `/api/code-server/targets/${encodeURIComponent(connectionId)}/install`,
      { packageId },
    )
    return response.data
  },

  uninstall: async (connectionId: string) => {
    await http.post(`/api/code-server/targets/${encodeURIComponent(connectionId)}/uninstall`)
  },

  start: async (connectionId: string, folder?: string) => {
    const response = await http.post<CodeServerSession>(
      `/api/code-server/targets/${encodeURIComponent(connectionId)}/start`,
      folder ? { folder } : {},
    )
    return response.data
  },

  stop: async (connectionId: string) => {
    const response = await http.post<CodeServerSession>(
      `/api/code-server/targets/${encodeURIComponent(connectionId)}/stop`,
    )
    return response.data
  },
}

/**
 * 以原始二进制 body 上传离线包（不走默认 JSON axios 实例），
 * 通过 XHR 的 upload 事件提供进度。
 */
export function uploadPackage(
  file: File,
  options: UploadPackageOptions,
): Promise<CodeServerPackage> {
  return new Promise<CodeServerPackage>((resolve, reject) => {
    const query = `?version=${encodeURIComponent(options.version)}&arch=${encodeURIComponent(options.arch)}`
    const xhr = new XMLHttpRequest()
    xhr.open('POST', `/api/code-server/packages${query}`, true)
    xhr.withCredentials = true
    xhr.responseType = 'text'
    xhr.setRequestHeader('Content-Type', 'application/octet-stream')

    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable) {
        options.onProgress?.(event.loaded, event.total)
      }
    }

    xhr.onerror = () => reject(new Error('离线包上传失败，请检查网络连接。'))
    xhr.onabort = () => reject(new Error('离线包上传已取消。'))
    xhr.onload = () => {
      if (xhr.status === 401) {
        handleAccessUnauthorized()
      }

      const result = parseResult<CodeServerPackage>(xhr.responseText)
      if (typeof result.code === 'number') {
        if (result.code === 200 && result.data) {
          resolve(result.data)
          return
        }
        reject(new Error(result.message || `离线包上传失败（code ${result.code}）。`))
        return
      }

      if (xhr.status >= 200 && xhr.status < 300) {
        if (result.data) {
          resolve(result.data)
          return
        }
        reject(new Error('离线包上传成功但未返回元数据。'))
        return
      }

      reject(
        new Error(
          xhr.status === 401
            ? '登录已失效，请重新登录。'
            : `离线包上传失败（HTTP ${xhr.status}）。`,
        ),
      )
    }

    xhr.send(file)
  })
}
