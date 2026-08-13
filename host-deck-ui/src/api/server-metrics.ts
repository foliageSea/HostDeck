export interface ServerMetricsSnapshot {
  timestamp: number
  uptimeMs: number
  rssBytes: number
  peakRssBytes: number
  cpuPercent: number | null
  eventLoopLagMs: number
}
