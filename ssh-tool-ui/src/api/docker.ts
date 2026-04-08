import { http } from '@/lib/http';

export interface DockerContainer {
  id: string;
  name: string;
  image: string;
  status: string;
  state: string;
  ports: string[];
  createdAt?: string;
}

export interface DockerImage {
  id: string;
  repository: string;
  tag: string;
  size: string;
  createdAt?: string;
  dangling?: boolean;
  inUse?: boolean;
}

export interface DockerShellSessionResponse {
  sessionId: string;
}

export interface DockerContainerStats {
  id: string;
  name: string;
  cpuPercent: string;
  memPercent: string;
  memUsage: string;
  netIO: string;
  blockIO: string;
  pids: string;
}

export interface DockerContainerDiagnostic {
  containerId: string;
  restartCount: number;
  healthStatus: string;
  exitCode: number;
}

export interface DockerContainerInspect {
  Id?: string;
  Name?: string;
  Config?: {
    Image?: string;
    Cmd?: string[];
    Env?: string[];
    Labels?: Record<string, string>;
  };
  State?: {
    Status?: string;
    Running?: boolean;
    ExitCode?: number;
    RestartCount?: number;
    Health?: {
      Status?: string;
    };
  };
  HostConfig?: {
    RestartPolicy?: {
      Name?: string;
    };
  };
  NetworkSettings?: {
    Ports?: Record<string, Array<{ HostIp?: string; HostPort?: string }> | null>;
    Networks?: Record<string, { IPAddress?: string }>;
  };
  Mounts?: Array<{
    Type?: string;
    Source?: string;
    Destination?: string;
    RW?: boolean;
  }>;
}

export const dockerApi = {
  checkDocker: async (sessionId: string) => {
    const response = await http.get<{ available: boolean }>('/api/docker/check', {
      params: { sessionId }
    });
    return response.data;
  },

  listContainers: async (sessionId: string) => {
    const response = await http.get<DockerContainer[]>('/api/docker/containers', {
      params: { sessionId }
    });
    return response.data;
  },

  listImages: async (sessionId: string) => {
    const response = await http.get<DockerImage[]>('/api/docker/images', {
      params: { sessionId }
    });
    return response.data;
  },

  startContainer: async (sessionId: string, id: string) => {
    const response = await http.post<{ success: boolean }>(`/api/docker/containers/${id}/start`, null, {
      params: { sessionId }
    });
    return response.data;
  },

  stopContainer: async (sessionId: string, id: string) => {
    const response = await http.post<{ success: boolean }>(`/api/docker/containers/${id}/stop`, null, {
      params: { sessionId }
    });
    return response.data;
  },

  restartContainer: async (sessionId: string, id: string) => {
    const response = await http.post<{ success: boolean }>(`/api/docker/containers/${id}/restart`, null, {
      params: { sessionId }
    });
    return response.data;
  },

  removeContainer: async (sessionId: string, id: string, force = false) => {
    const response = await http.delete<{ success: boolean }>(`/api/docker/containers/${id}`, {
      params: { sessionId, force }
    });
    return response.data;
  },

  getContainerLogs: async (sessionId: string, containerId: string, tail = 100) => {
    const response = await http.get<{ logs: string }>('/api/docker/containers/logs', {
      params: { sessionId, containerId, tail }
    });
    return response.data;
  },

  getContainerLogsAdvanced: async (
    sessionId: string,
    containerId: string,
    options: { tail?: number; timestamps?: boolean } = {}
  ) => {
    const response = await http.get<{ logs: string }>('/api/docker/containers/logs', {
      params: {
        sessionId,
        containerId,
        tail: options.tail ?? 200,
        timestamps: options.timestamps ?? false,
      }
    });
    return response.data;
  },

  createContainerShellSession: async (sessionId: string, containerId: string) => {
    const response = await http.post<DockerShellSessionResponse>(
      `/api/docker/containers/${containerId}/shell`,
      null,
      {
        params: { sessionId },
      }
    )
    return response.data
  },

  removeImage: async (sessionId: string, id: string, force = false) => {
    const response = await http.delete<{ success: boolean }>(`/api/docker/images/${id}`, {
      params: { sessionId, force }
    });
    return response.data;
  },

  batchStartContainers: async (sessionId: string, containerIds: string[]) => {
    const response = await http.post<{ success: boolean; processed: number }>(
      '/api/docker/containers/batch-start',
      { containerIds },
      { params: { sessionId } }
    );
    return response.data;
  },

  batchStopContainers: async (sessionId: string, containerIds: string[]) => {
    const response = await http.post<{ success: boolean; processed: number }>(
      '/api/docker/containers/batch-stop',
      { containerIds },
      { params: { sessionId } }
    );
    return response.data;
  },

  removeStoppedContainers: async (sessionId: string) => {
    const response = await http.delete<{ success: boolean; removedCount: number }>(
      '/api/docker/containers/stopped',
      { params: { sessionId } }
    );
    return response.data;
  },

  pruneImages: async (sessionId: string, includeUnused = false) => {
    const response = await http.post<{ success: boolean; output: string }>(
      '/api/docker/images/prune',
      { includeUnused },
      { params: { sessionId } }
    );
    return response.data;
  },

  inspectContainer: async (sessionId: string, containerId: string) => {
    const response = await http.get<DockerContainerInspect>(
      `/api/docker/containers/${containerId}/inspect`,
      { params: { sessionId } }
    );
    return response.data;
  },

  getContainerStats: async (sessionId: string, containerId: string) => {
    const response = await http.get<DockerContainerStats>(
      `/api/docker/containers/${containerId}/stats`,
      { params: { sessionId } }
    );
    return response.data;
  },

  getContainerDiagnostics: async (sessionId: string, containerIds: string[]) => {
    const response = await http.post<DockerContainerDiagnostic[]>(
      '/api/docker/containers/diagnostics',
      { containerIds },
      { params: { sessionId } }
    );
    return response.data;
  },
};
