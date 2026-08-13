import type { AxiosProgressEvent } from 'axios'
import { http } from '@/lib/http'
import { consumeServerSentEvents } from '@/lib/sse'

export interface DockerContainerNetwork {
  name: string
  ipAddress: string
}

export interface DockerContainer {
  id: string
  name: string
  image: string
  status: string
  state: string
  ports: string[]
  networks: DockerContainerNetwork[]
  createdAt?: string
}

export interface DockerImage {
  id: string
  repository: string
  tag: string
  size: string
  createdAt?: string
  dangling?: boolean
  inUse?: boolean
}

export interface PagedResponse<T, TSummary = Record<string, number>> {
  items: T[]
  total: number
  page: number
  pageSize: number
  totalPages: number
  summary?: TSummary
}

export type DockerContainerStatusFilter =
  | 'all'
  | 'running'
  | 'stopped'
  | 'paused'
  | 'restarting'
  | 'exited'

export interface DockerContainerListParams {
  page?: number
  pageSize?: number
  status?: DockerContainerStatusFilter
  keyword?: string
}

export interface DockerImageListParams {
  page?: number
  pageSize?: number
  keyword?: string
}

export interface DockerContainerSummary {
  total: number
  running: number
  stopped: number
}

export interface DockerImageSummary {
  total: number
  dangling: number
}

export interface DockerSessionResponse {
  sessionId: string
}

export interface DockerContainerStats {
  id: string
  name: string
  cpuPercent: string
  memPercent: string
  memUsage: string
  netIO: string
  blockIO: string
  pids: string
}

export interface DockerContainerStatsSample {
  id: string
  name: string
  timestamp: number
  cpuPercent: number
  memoryPercent: number
  memoryUsage: number
  memoryLimit: number
  networkRxBytes: number
  networkTxBytes: number
  networkRxBytesPerSecond: number
  networkTxBytesPerSecond: number
  blockReadBytes: number
  blockWriteBytes: number
  pids: number
}

export interface DockerContainerDiagnostic {
  containerId: string
  restartCount: number
  healthStatus: string
  exitCode: number
}

export interface DockerImageHistoryItem {
  id: string
  createdSince: string
  createdAt: string
  createdBy: string
  size: string
  comment: string
}

export interface DockerImageContainerRef {
  id: string
  name: string
  image: string
  state: string
  status: string
}

export interface DockerImageCreateDefaults {
  ports: string[]
  volumes: string[]
}

export interface DockerNetwork {
  id: string
  name: string
  driver: string
  scope: string
  createdAt?: string
  internal: boolean
  attachable: boolean
  ingress: boolean
  subnet: string
  gateway: string
  connectedContainers: number
  connectedContainerNames: string[]
}

export interface DockerVolume {
  name: string
  driver: string
  scope: string
  mountpoint: string
  createdAt?: string
  refCount: number
}

export interface DockerCreateNetworkPayload {
  name: string
  driver?: string
  internal?: boolean
  attachable?: boolean
  ingress?: boolean
  options?: Record<string, string>
  labels?: Record<string, string>
}

export interface DockerCreateVolumePayload {
  name: string
  driver?: string
  options?: Record<string, string>
  labels?: Record<string, string>
}

export interface DockerNetworkContainerPayload {
  container: string
  force?: boolean
}

export interface DockerImagePullProgress {
  id?: string
  progress?: string
  progressDetail?: { current?: number; total?: number }
  status?: string
  [key: string]: unknown
}

export type DockerImagePullStreamEvent =
  | { event: 'progress'; data: DockerImagePullProgress }
  | { event: 'stderr'; data: { text: string } }
  | { event: 'done'; data: { image: string } }
  | { event: 'error'; data: { message: string } }

export type DockerContainerLogStreamEvent =
  | { event: 'connected'; data: Record<string, never> }
  | { event: 'stdout' | 'stderr'; data: { text: string } }
  | { event: 'done'; data: Record<string, never> }
  | { event: 'error'; data: { message: string } }

export type DockerContainerStatsStreamEvent =
  | { event: 'connected'; data: Record<string, never> }
  | { event: 'stats'; data: DockerContainerStatsSample }
  | { event: 'done'; data: Record<string, never> }
  | { event: 'error'; data: { message: string } }

export interface DockerCreateContainerPayload {
  image: string
  name?: string
  ports?: string[]
  env?: string[]
  volumes?: string[]
  restartPolicy?: string
  cmd?: string[]
  entrypoint?: string[]
  start?: boolean
}

export interface DockerContainerInspect {
  Id?: string
  Name?: string
  Config?: {
    Image?: string
    Cmd?: string[]
    Entrypoint?: string[]
    Env?: string[]
    ExposedPorts?: Record<string, Record<string, never>>
    Labels?: Record<string, string>
  }
  State?: {
    Status?: string
    Running?: boolean
    ExitCode?: number
    RestartCount?: number
    Health?: {
      Status?: string
    }
  }
  HostConfig?: {
    PortBindings?: Record<string, Array<{ HostIp?: string; HostPort?: string }> | null>
    RestartPolicy?: {
      Name?: string
    }
  }
  NetworkSettings?: {
    Ports?: Record<string, Array<{ HostIp?: string; HostPort?: string }> | null>
    Networks?: Record<string, { IPAddress?: string }>
  }
  Mounts?: Array<{
    Type?: string
    Name?: string
    Source?: string
    Destination?: string
    RW?: boolean
  }>
}

export const dockerApi = {
  async createSession(connectionId: string) {
    const response = await http.post<DockerSessionResponse>('/api/docker/session', { connectionId })
    return response.data
  },

  async deleteSession(sessionId: string) {
    const response = await http.delete('/api/docker/session', {
      params: { sessionId },
    })
    return response.data
  },

  async checkDocker(connectionId: string) {
    const response = await http.get<{ available: boolean }>('/api/docker/check', {
      params: { connectionId },
    })
    return response.data
  },

  async listContainers(connectionId: string, params: DockerContainerListParams = {}) {
    const response = await http.get<PagedResponse<DockerContainer, DockerContainerSummary>>(
      '/api/docker/containers',
      {
        params: { ...params, connectionId },
      },
    )
    return response.data
  },

  async listImages(connectionId: string, params: DockerImageListParams = {}) {
    const response = await http.get<PagedResponse<DockerImage, DockerImageSummary>>(
      '/api/docker/images',
      {
        params: { ...params, connectionId },
      },
    )
    return response.data
  },

  async listNetworks(connectionId: string) {
    const response = await http.get<DockerNetwork[]>('/api/docker/networks', {
      params: { connectionId },
    })
    return response.data
  },

  async createNetwork(connectionId: string, payload: DockerCreateNetworkPayload) {
    const response = await http.post<{ id: string; warning?: string }>(
      '/api/docker/networks',
      payload,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async inspectNetwork(connectionId: string, networkId: string) {
    const response = await http.get<Record<string, unknown>>(
      `/api/docker/networks/${encodeURIComponent(networkId)}/inspect`,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async connectNetwork(
    connectionId: string,
    networkId: string,
    payload: DockerNetworkContainerPayload,
  ) {
    const response = await http.post<{ success: boolean }>(
      `/api/docker/networks/${encodeURIComponent(networkId)}/connect`,
      payload,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async disconnectNetwork(
    connectionId: string,
    networkId: string,
    payload: DockerNetworkContainerPayload,
  ) {
    const response = await http.post<{ success: boolean }>(
      `/api/docker/networks/${encodeURIComponent(networkId)}/disconnect`,
      payload,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async removeNetwork(connectionId: string, networkId: string) {
    const response = await http.delete<{ success: boolean }>(
      `/api/docker/networks/${encodeURIComponent(networkId)}`,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async pruneNetworks(connectionId: string) {
    const response = await http.post<{ success: boolean; deleted: string[]; deletedCount: number }>(
      '/api/docker/networks/prune',
      null,
      { params: { connectionId } },
    )
    return response.data
  },

  async listVolumes(connectionId: string) {
    const response = await http.get<DockerVolume[]>('/api/docker/volumes', {
      params: { connectionId },
    })
    return response.data
  },

  async createVolume(connectionId: string, payload: DockerCreateVolumePayload) {
    const response = await http.post<{ name: string; mountpoint?: string; warning?: string }>(
      '/api/docker/volumes',
      payload,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async inspectVolume(connectionId: string, volumeName: string) {
    const response = await http.get<Record<string, unknown>>(
      `/api/docker/volumes/${encodeURIComponent(volumeName)}/inspect`,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async removeVolume(connectionId: string, volumeName: string) {
    const response = await http.delete<{ success: boolean }>(
      `/api/docker/volumes/${encodeURIComponent(volumeName)}`,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async pruneVolumes(connectionId: string) {
    const response = await http.post<{ success: boolean; deleted: string[]; deletedCount: number }>(
      '/api/docker/volumes/prune',
      null,
      { params: { connectionId } },
    )
    return response.data
  },

  async pruneBuildCache(connectionId: string, includeAll = false) {
    const response = await http.post<{
      success: boolean
      deleted: string[]
      deletedCount: number
      spaceReclaimed: number
    }>('/api/docker/build-cache/prune', { includeAll }, { params: { connectionId } })
    return response.data
  },

  async startContainer(connectionId: string, id: string) {
    const response = await http.post<{ success: boolean }>(
      `/api/docker/containers/${id}/start`,
      null,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async stopContainer(connectionId: string, id: string) {
    const response = await http.post<{ success: boolean }>(
      `/api/docker/containers/${id}/stop`,
      null,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async restartContainer(connectionId: string, id: string) {
    const response = await http.post<{ success: boolean }>(
      `/api/docker/containers/${id}/restart`,
      null,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async pauseContainer(connectionId: string, id: string) {
    const response = await http.post<{ success: boolean }>(
      `/api/docker/containers/${id}/pause`,
      null,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async unpauseContainer(connectionId: string, id: string) {
    const response = await http.post<{ success: boolean }>(
      `/api/docker/containers/${id}/unpause`,
      null,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async renameContainer(connectionId: string, id: string, newName: string) {
    const response = await http.post<{ success: boolean }>(
      `/api/docker/containers/${id}/rename`,
      { newName },
      { params: { connectionId } },
    )
    return response.data
  },

  async recreateContainer(connectionId: string, id: string) {
    const response = await http.post<{
      oldContainerId: string
      newContainerId: string
      name: string
      started: boolean
    }>(`/api/docker/containers/${id}/recreate`, null, { params: { connectionId } })
    return response.data
  },

  async replaceContainer(connectionId: string, id: string, payload: DockerCreateContainerPayload) {
    const response = await http.post<{
      oldContainerId: string
      newContainerId: string
      name: string
      started: boolean
    }>(`/api/docker/containers/${id}/replace`, payload, { params: { connectionId } })
    return response.data
  },

  async removeContainer(connectionId: string, id: string, force = false) {
    const response = await http.delete<{ success: boolean }>(`/api/docker/containers/${id}`, {
      params: { connectionId, force },
    })
    return response.data
  },

  async streamContainerLogs(
    connectionId: string,
    containerId: string,
    options: { tail?: number; timestamps?: boolean } = {},
    onEvent: (event: DockerContainerLogStreamEvent) => void,
    signal?: AbortSignal,
  ) {
    const query = new URLSearchParams({
      connectionId,
      containerId,
      tail: String(options.tail ?? 200),
      timestamps: String(options.timestamps ?? false),
    })
    const response = await fetch(`/api/docker/containers/logs?${query}`, {
      credentials: 'same-origin',
      headers: { Accept: 'text/event-stream' },
      signal,
    })

    if (!response.ok) {
      const body = await response.text()
      let message = body || `获取容器日志失败 (${response.status})`
      try {
        const parsed = JSON.parse(body) as { message?: string }
        message = parsed.message || message
      } catch {
        // Keep a plain error response verbatim.
      }
      throw new Error(message)
    }
    if (!response.body) {
      throw new Error('浏览器未提供流式响应。')
    }

    let completed = false
    let streamError: string | undefined
    let connected = false
    const reportConnected = () => {
      if (!connected) {
        connected = true
        onEvent({ event: 'connected', data: {} })
      }
    }
    reportConnected()
    await consumeServerSentEvents(response.body, (message) => {
      const data = JSON.parse(message.data) as Record<string, unknown>
      const event = { event: message.event, data } as DockerContainerLogStreamEvent
      if (event.event === 'connected') {
        reportConnected()
      } else {
        onEvent(event)
      }
      if (event.event === 'done') {
        completed = true
      } else if (event.event === 'error') {
        streamError = event.data.message
      }
    })

    if (streamError) {
      throw new Error(streamError)
    }
    if (!completed) {
      throw new Error('容器日志流意外结束。')
    }
  },

  async inspectContainer(connectionId: string, containerId: string) {
    const response = await http.get<DockerContainerInspect>(
      `/api/docker/containers/${containerId}/inspect`,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async getContainerStats(connectionId: string, containerId: string) {
    const response = await http.get<DockerContainerStats>(
      `/api/docker/containers/${containerId}/stats`,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async streamContainerStats(
    connectionId: string,
    containerId: string,
    onEvent: (event: DockerContainerStatsStreamEvent) => void,
    signal?: AbortSignal,
  ) {
    const query = new URLSearchParams({ connectionId })
    const response = await fetch(
      `/api/docker/containers/${encodeURIComponent(containerId)}/stats/stream?${query}`,
      {
        credentials: 'same-origin',
        headers: { Accept: 'text/event-stream' },
        signal,
      },
    )

    if (!response.ok) {
      const body = await response.text()
      let message = body || `获取容器资源监控失败 (${response.status})`
      try {
        const parsed = JSON.parse(body) as { message?: string }
        message = parsed.message || message
      } catch {
        // Keep a plain error response verbatim.
      }
      throw new Error(message)
    }
    if (!response.body) {
      throw new Error('浏览器未提供流式响应。')
    }

    let streamError: string | undefined
    await consumeServerSentEvents(response.body, (message) => {
      const data = JSON.parse(message.data) as Record<string, unknown>
      const event = { event: message.event, data } as DockerContainerStatsStreamEvent
      onEvent(event)
      if (event.event === 'error') {
        streamError = event.data.message
      }
    })

    if (streamError) {
      throw new Error(streamError)
    }
  },

  async createContainer(connectionId: string, payload: DockerCreateContainerPayload) {
    const response = await http.post<{ containerId: string; started: boolean }>(
      '/api/docker/containers',
      payload,
      { params: { connectionId } },
    )
    return response.data
  },

  async removeImage(connectionId: string, id: string, force = false) {
    const response = await http.delete<{ success: boolean }>(`/api/docker/images/${id}`, {
      params: { connectionId, force },
    })
    return response.data
  },

  async pullImage(connectionId: string, image: string) {
    const response = await http.post<{ success: boolean; output: string }>(
      '/api/docker/images/pull',
      { image },
      { params: { connectionId } },
    )
    return response.data
  },

  async pullImageStream(
    connectionId: string,
    image: string,
    onEvent: (event: DockerImagePullStreamEvent) => void,
    signal?: AbortSignal,
  ) {
    const query = new URLSearchParams({ connectionId })
    const response = await fetch(`/api/docker/images/pull/stream?${query}`, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        Accept: 'text/event-stream',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ image }),
      signal,
    })

    if (!response.ok) {
      const body = await response.text()
      let message = body || `拉取镜像失败 (${response.status})`
      try {
        const parsed = JSON.parse(body) as { message?: string }
        message = parsed.message || message
      } catch {
        // Keep the plain response body when it is not JSON.
      }
      throw new Error(message)
    }
    if (!response.body) {
      throw new Error('浏览器未提供流式响应。')
    }

    let result: { image: string } | undefined
    let streamError: string | undefined
    await consumeServerSentEvents(response.body, (message) => {
      const data = JSON.parse(message.data) as Record<string, unknown>
      const event = { event: message.event, data } as DockerImagePullStreamEvent
      onEvent(event)
      if (event.event === 'done') {
        result = event.data
      } else if (event.event === 'error') {
        streamError = event.data.message
      }
    })

    if (streamError) {
      throw new Error(streamError)
    }
    if (!result) {
      throw new Error('镜像拉取输出流意外结束。')
    }
    return result
  },

  async importImage(
    connectionId: string,
    formData: FormData,
    onUploadProgress?: (event: AxiosProgressEvent) => void,
    signal?: AbortSignal,
  ) {
    const response = await http.post<{ success: boolean; output: string }>(
      '/api/docker/images/import',
      formData,
      {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
        onUploadProgress,
        params: { connectionId },
        signal,
      },
    )
    return response.data
  },

  async tagImage(connectionId: string, sourceImage: string, targetImage: string) {
    const response = await http.post<{ success: boolean }>(
      '/api/docker/images/tag',
      { sourceImage, targetImage },
      { params: { connectionId } },
    )
    return response.data
  },

  async exportImage(
    connectionId: string,
    imageId: string,
    image: string,
    onDownloadProgress?: (event: AxiosProgressEvent) => void,
    signal?: AbortSignal,
  ) {
    const response = await http.get<Blob>(
      `/api/docker/images/${encodeURIComponent(imageId)}/export`,
      {
        onDownloadProgress,
        params: { connectionId, image },
        responseType: 'blob',
        signal,
      },
    )
    return response.data
  },

  async getImageHistory(connectionId: string, imageId: string) {
    const response = await http.get<DockerImageHistoryItem[]>(
      `/api/docker/images/${imageId}/history`,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async getImageCreateDefaults(connectionId: string, imageId: string) {
    const response = await http.get<DockerImageCreateDefaults>(
      `/api/docker/images/${imageId}/create-defaults`,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async getImageContainers(connectionId: string, imageId: string) {
    const response = await http.get<DockerImageContainerRef[]>(
      `/api/docker/images/${imageId}/containers`,
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async batchStartContainers(connectionId: string, containerIds: string[]) {
    const response = await http.post<{ success: boolean; processed: number }>(
      '/api/docker/containers/batch-start',
      { containerIds },
      { params: { connectionId } },
    )
    return response.data
  },

  async batchStopContainers(connectionId: string, containerIds: string[]) {
    const response = await http.post<{ success: boolean; processed: number }>(
      '/api/docker/containers/batch-stop',
      { containerIds },
      { params: { connectionId } },
    )
    return response.data
  },

  async removeStoppedContainers(connectionId: string) {
    const response = await http.delete<{ success: boolean; removedCount: number }>(
      '/api/docker/containers/stopped',
      {
        params: { connectionId },
      },
    )
    return response.data
  },

  async pruneImages(connectionId: string, includeUnused = false) {
    const response = await http.post<{ success: boolean; output: string }>(
      '/api/docker/images/prune',
      { includeUnused },
      { params: { connectionId } },
    )
    return response.data
  },

  async getContainerDiagnostics(connectionId: string, containerIds: string[]) {
    const response = await http.post<DockerContainerDiagnostic[]>(
      '/api/docker/containers/diagnostics',
      { containerIds },
      { params: { connectionId } },
    )
    return response.data
  },
}
