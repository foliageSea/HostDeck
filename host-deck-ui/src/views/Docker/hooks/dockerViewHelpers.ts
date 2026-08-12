import type { DockerTabName } from './dockerViewTypes'

export function formatTime(value?: string) {
  if (!value) {
    return '-'
  }

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) {
    return value
  }

  return date.toLocaleString('zh-CN')
}

export function formatDateTime(value: Date | null) {
  if (!value) {
    return '-'
  }

  return value.toLocaleString('zh-CN')
}

export function createLoadedTabs(): Record<DockerTabName, boolean> {
  return {
    containers: false,
    images: false,
    networks: false,
    overview: false,
    volumes: false,
  }
}

export function parseContainerHostPort(portText: string) {
  const hostSide = portText.split('->')[0]?.trim() ?? ''
  if (!hostSide || hostSide.includes('/')) {
    return null
  }

  const hostPort = hostSide.includes(':') ? hostSide.slice(hostSide.lastIndexOf(':') + 1) : hostSide
  const portNumber = Number(hostPort)
  if (!Number.isInteger(portNumber) || portNumber < 1 || portNumber > 65535) {
    return null
  }

  return hostPort
}
