import { http } from '@/lib/http'

export interface DockerContainer {
  id: string
  name: string
  image: string
  status: string
  state: string
  ports: string[]
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

export type DockerContainerStatusFilter = 'all' | 'running' | 'stopped' | 'paused' | 'restarting' | 'exited'

export interface DockerContainerListParams {
  page?: number
  pageSize?: number
  status?: DockerContainerStatusFilter
}

export interface DockerImageListParams {
  page?: number
  pageSize?: number
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

export interface DockerComposeProject {
  name: string
  status: string
  configFiles: string
  workingDir: string
}

export interface DockerComposeService {
  id: string
  name: string
  service: string
  project: string
  image: string
  state: string
  status: string
  ports: string
}

export interface DockerComposeProjectPayload {
  projectName: string
  configFiles: string[]
  workingDir?: string
}

export interface DockerComposeCreatePayload {
  projectName: string
  workingDir: string
  fileName: string
  content: string
  startAfterCreate?: boolean
}

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
    Env?: string[]
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

  async checkCompose(connectionId: string) {
    const response = await http.get<{ available: boolean }>('/api/docker/compose/check', {
      params: { connectionId },
    })
    return response.data
  },

  async listComposeProjects(connectionId: string) {
    const response = await http.get<DockerComposeProject[]>('/api/docker/compose/projects', {
      params: { connectionId },
    })
    return response.data
  },

  async createComposeProject(connectionId: string, payload: DockerComposeCreatePayload) {
    const response = await http.post<{
      projectName: string
      workingDir: string
      configFiles: string[]
      started: boolean
      startError?: string
      output: string
    }>('/api/docker/compose/project', payload, {
      params: { connectionId },
    })
    return response.data
  },

  async listComposeServices(connectionId: string, payload: DockerComposeProjectPayload) {
    const response = await http.post<DockerComposeService[]>('/api/docker/compose/project/services', payload, {
      params: { connectionId },
    })
    return response.data
  },

  async upComposeProject(connectionId: string, payload: DockerComposeProjectPayload) {
    const response = await http.post<{ success: boolean; output: string }>('/api/docker/compose/project/up', payload, {
      params: { connectionId },
    })
    return response.data
  },

  async stopComposeProject(connectionId: string, payload: DockerComposeProjectPayload) {
    const response = await http.post<{ success: boolean; output: string }>('/api/docker/compose/project/stop', payload, {
      params: { connectionId },
    })
    return response.data
  },

  async restartComposeProject(connectionId: string, payload: DockerComposeProjectPayload) {
    const response = await http.post<{ success: boolean; output: string }>('/api/docker/compose/project/restart', payload, {
      params: { connectionId },
    })
    return response.data
  },

  async downComposeProject(connectionId: string, payload: DockerComposeProjectPayload) {
    const response = await http.post<{ success: boolean; output: string }>('/api/docker/compose/project/down', payload, {
      params: { connectionId },
    })
    return response.data
  },

  async getComposeLogs(connectionId: string, payload: DockerComposeProjectPayload, tail = 200) {
    const response = await http.post<{ logs: string }>('/api/docker/compose/project/logs', payload, {
      params: { connectionId, tail },
    })
    return response.data
  },

  async listContainers(connectionId: string, params: DockerContainerListParams = {}) {
    const response = await http.get<PagedResponse<DockerContainer, DockerContainerSummary>>('/api/docker/containers', {
      params: { ...params, connectionId },
    })
    return response.data
  },

  async listImages(connectionId: string, params: DockerImageListParams = {}) {
    const response = await http.get<PagedResponse<DockerImage, DockerImageSummary>>('/api/docker/images', {
      params: { ...params, connectionId },
    })
    return response.data
  },

  async startContainer(connectionId: string, id: string) {
    const response = await http.post<{ success: boolean }>(`/api/docker/containers/${id}/start`, null, {
      params: { connectionId },
    })
    return response.data
  },

  async stopContainer(connectionId: string, id: string) {
    const response = await http.post<{ success: boolean }>(`/api/docker/containers/${id}/stop`, null, {
      params: { connectionId },
    })
    return response.data
  },

  async restartContainer(connectionId: string, id: string) {
    const response = await http.post<{ success: boolean }>(`/api/docker/containers/${id}/restart`, null, {
      params: { connectionId },
    })
    return response.data
  },

  async pauseContainer(connectionId: string, id: string) {
    const response = await http.post<{ success: boolean }>(`/api/docker/containers/${id}/pause`, null, {
      params: { connectionId },
    })
    return response.data
  },

  async unpauseContainer(connectionId: string, id: string) {
    const response = await http.post<{ success: boolean }>(`/api/docker/containers/${id}/unpause`, null, {
      params: { connectionId },
    })
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
    const response = await http.post<{ oldContainerId: string; newContainerId: string; name: string; started: boolean }>(
      `/api/docker/containers/${id}/recreate`,
      null,
      { params: { connectionId } },
    )
    return response.data
  },

  async removeContainer(connectionId: string, id: string, force = false) {
    const response = await http.delete<{ success: boolean }>(`/api/docker/containers/${id}`, {
      params: { connectionId, force },
    })
    return response.data
  },

  async getContainerLogs(connectionId: string, containerId: string, tail = 200) {
    const response = await http.get<{ logs: string }>('/api/docker/containers/logs', {
      params: { connectionId, containerId, tail },
    })
    return response.data
  },

  async getContainerLogsAdvanced(
    connectionId: string,
    containerId: string,
    options: { tail?: number; timestamps?: boolean } = {},
  ) {
    const response = await http.get<{ logs: string }>('/api/docker/containers/logs', {
      params: {
        connectionId,
        containerId,
        tail: options.tail ?? 200,
        timestamps: options.timestamps ?? false,
      },
    })
    return response.data
  },

  async inspectContainer(connectionId: string, containerId: string) {
    const response = await http.get<DockerContainerInspect>(`/api/docker/containers/${containerId}/inspect`, {
      params: { connectionId },
    })
    return response.data
  },

  async getContainerStats(connectionId: string, containerId: string) {
    const response = await http.get<DockerContainerStats>(`/api/docker/containers/${containerId}/stats`, {
      params: { connectionId },
    })
    return response.data
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

  async tagImage(connectionId: string, sourceImage: string, targetImage: string) {
    const response = await http.post<{ success: boolean }>(
      '/api/docker/images/tag',
      { sourceImage, targetImage },
      { params: { connectionId } },
    )
    return response.data
  },

  async getImageHistory(connectionId: string, imageId: string) {
    const response = await http.get<DockerImageHistoryItem[]>(`/api/docker/images/${imageId}/history`, {
      params: { connectionId },
    })
    return response.data
  },

  async getImageCreateDefaults(connectionId: string, imageId: string) {
    const response = await http.get<DockerImageCreateDefaults>(`/api/docker/images/${imageId}/create-defaults`, {
      params: { connectionId },
    })
    return response.data
  },

  async getImageContainers(connectionId: string, imageId: string) {
    const response = await http.get<DockerImageContainerRef[]>(`/api/docker/images/${imageId}/containers`, {
      params: { connectionId },
    })
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
    const response = await http.delete<{ success: boolean; removedCount: number }>('/api/docker/containers/stopped', {
      params: { connectionId },
    })
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
