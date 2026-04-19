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

export interface DockerShellSessionResponse {
  sessionId: string
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

  async checkDocker(sessionId: string) {
    const response = await http.get<{ available: boolean }>('/api/docker/check', {
      params: { sessionId },
    })
    return response.data
  },

  async listContainers(sessionId: string) {
    const response = await http.get<DockerContainer[]>('/api/docker/containers', {
      params: { sessionId },
    })
    return response.data
  },

  async listImages(sessionId: string) {
    const response = await http.get<DockerImage[]>('/api/docker/images', {
      params: { sessionId },
    })
    return response.data
  },

  async startContainer(sessionId: string, id: string) {
    const response = await http.post<{ success: boolean }>(`/api/docker/containers/${id}/start`, null, {
      params: { sessionId },
    })
    return response.data
  },

  async stopContainer(sessionId: string, id: string) {
    const response = await http.post<{ success: boolean }>(`/api/docker/containers/${id}/stop`, null, {
      params: { sessionId },
    })
    return response.data
  },

  async restartContainer(sessionId: string, id: string) {
    const response = await http.post<{ success: boolean }>(`/api/docker/containers/${id}/restart`, null, {
      params: { sessionId },
    })
    return response.data
  },

  async pauseContainer(sessionId: string, id: string) {
    const response = await http.post<{ success: boolean }>(`/api/docker/containers/${id}/pause`, null, {
      params: { sessionId },
    })
    return response.data
  },

  async unpauseContainer(sessionId: string, id: string) {
    const response = await http.post<{ success: boolean }>(`/api/docker/containers/${id}/unpause`, null, {
      params: { sessionId },
    })
    return response.data
  },

  async renameContainer(sessionId: string, id: string, newName: string) {
    const response = await http.post<{ success: boolean }>(
      `/api/docker/containers/${id}/rename`,
      { newName },
      { params: { sessionId } },
    )
    return response.data
  },

  async recreateContainer(sessionId: string, id: string) {
    const response = await http.post<{ oldContainerId: string; newContainerId: string; name: string; started: boolean }>(
      `/api/docker/containers/${id}/recreate`,
      null,
      { params: { sessionId } },
    )
    return response.data
  },

  async removeContainer(sessionId: string, id: string, force = false) {
    const response = await http.delete<{ success: boolean }>(`/api/docker/containers/${id}`, {
      params: { force, sessionId },
    })
    return response.data
  },

  async getContainerLogs(sessionId: string, containerId: string, tail = 200) {
    const response = await http.get<{ logs: string }>('/api/docker/containers/logs', {
      params: { containerId, sessionId, tail },
    })
    return response.data
  },

  async getContainerLogsAdvanced(
    sessionId: string,
    containerId: string,
    options: { tail?: number; timestamps?: boolean } = {},
  ) {
    const response = await http.get<{ logs: string }>('/api/docker/containers/logs', {
      params: {
        containerId,
        sessionId,
        tail: options.tail ?? 200,
        timestamps: options.timestamps ?? false,
      },
    })
    return response.data
  },

  async inspectContainer(sessionId: string, containerId: string) {
    const response = await http.get<DockerContainerInspect>(`/api/docker/containers/${containerId}/inspect`, {
      params: { sessionId },
    })
    return response.data
  },

  async getContainerStats(sessionId: string, containerId: string) {
    const response = await http.get<DockerContainerStats>(`/api/docker/containers/${containerId}/stats`, {
      params: { sessionId },
    })
    return response.data
  },

  async createContainerShellSession(sessionId: string, containerId: string) {
    const response = await http.post<DockerShellSessionResponse>(
      `/api/docker/containers/${containerId}/shell`,
      null,
      {
        params: { sessionId },
      },
    )
    return response.data
  },

  async createContainer(sessionId: string, payload: DockerCreateContainerPayload) {
    const response = await http.post<{ containerId: string; started: boolean }>(
      '/api/docker/containers',
      payload,
      { params: { sessionId } },
    )
    return response.data
  },

  async removeImage(sessionId: string, id: string, force = false) {
    const response = await http.delete<{ success: boolean }>(`/api/docker/images/${id}`, {
      params: { force, sessionId },
    })
    return response.data
  },

  async pullImage(sessionId: string, image: string) {
    const response = await http.post<{ success: boolean; output: string }>(
      '/api/docker/images/pull',
      { image },
      { params: { sessionId } },
    )
    return response.data
  },

  async tagImage(sessionId: string, sourceImage: string, targetImage: string) {
    const response = await http.post<{ success: boolean }>(
      '/api/docker/images/tag',
      { sourceImage, targetImage },
      { params: { sessionId } },
    )
    return response.data
  },

  async getImageHistory(sessionId: string, imageId: string) {
    const response = await http.get<DockerImageHistoryItem[]>(`/api/docker/images/${imageId}/history`, {
      params: { sessionId },
    })
    return response.data
  },

  async getImageContainers(sessionId: string, imageId: string) {
    const response = await http.get<DockerImageContainerRef[]>(`/api/docker/images/${imageId}/containers`, {
      params: { sessionId },
    })
    return response.data
  },

  async batchStartContainers(sessionId: string, containerIds: string[]) {
    const response = await http.post<{ success: boolean; processed: number }>(
      '/api/docker/containers/batch-start',
      { containerIds },
      { params: { sessionId } },
    )
    return response.data
  },

  async batchStopContainers(sessionId: string, containerIds: string[]) {
    const response = await http.post<{ success: boolean; processed: number }>(
      '/api/docker/containers/batch-stop',
      { containerIds },
      { params: { sessionId } },
    )
    return response.data
  },

  async removeStoppedContainers(sessionId: string) {
    const response = await http.delete<{ success: boolean; removedCount: number }>('/api/docker/containers/stopped', {
      params: { sessionId },
    })
    return response.data
  },

  async pruneImages(sessionId: string, includeUnused = false) {
    const response = await http.post<{ success: boolean; output: string }>(
      '/api/docker/images/prune',
      { includeUnused },
      { params: { sessionId } },
    )
    return response.data
  },

  async getContainerDiagnostics(sessionId: string, containerIds: string[]) {
    const response = await http.post<DockerContainerDiagnostic[]>(
      '/api/docker/containers/diagnostics',
      { containerIds },
      { params: { sessionId } },
    )
    return response.data
  },
}
