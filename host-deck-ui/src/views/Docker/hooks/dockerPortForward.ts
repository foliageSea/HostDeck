import { portForwardApi, type PortForwardRule } from '@/api/port-forward'

export interface DockerPublishedPort {
  remoteHost: string
  remotePort: number
}

export function parseDockerHttpPort(portText: string): DockerPublishedPort | null {
  const match = portText.trim().match(/^(?:(.*):)?(\d+)->\d+\/tcp$/i)
  if (!match) return null
  const remotePort = Number(match[2])
  if (!Number.isInteger(remotePort) || remotePort < 1 || remotePort > 65535) return null
  const host = (match[1] || '127.0.0.1').replace(/^\[|\]$/g, '')
  return {
    remoteHost: host === '0.0.0.0' ? '127.0.0.1' : host === '::' ? '::1' : host,
    remotePort,
  }
}

// Deduplicate clicks across Docker windows sharing the same SSH connection.
const pendingForwards = new Map<string, Promise<PortForwardRule>>()

export function createDockerHttpForward(
  connectionId: string,
  containerName: string,
  target: DockerPublishedPort,
): Promise<PortForwardRule> {
  const key = JSON.stringify([connectionId, target.remoteHost, target.remotePort])
  const pending = pendingForwards.get(key)
  if (pending) return pending
  const task = (async () => {
    const rules = await portForwardApi.list()
    const existing = rules.find((rule) =>
      rule.protocol === 'http' &&
      rule.connectionId === connectionId &&
      rule.status === 'running' &&
      rule.remoteHost === target.remoteHost &&
      rule.remotePort === target.remotePort,
    )
    if (existing) return existing
    return portForwardApi.create({
      protocol: 'http',
      name: `${containerName}:${target.remotePort}`,
      enabled: true,
      connectionId,
      ...target,
    })
  })().finally(() => pendingForwards.delete(key))
  pendingForwards.set(key, task)
  return task
}
