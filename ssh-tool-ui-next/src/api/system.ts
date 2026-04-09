export interface MonitorResponse {
  cpu: string
  cpuUsage?: number
  ram: {
    total: number
    used: number
    free: number
  }
  disk: string
  network?: {
    uploadSpeed: number
    downloadSpeed: number
  }
}
