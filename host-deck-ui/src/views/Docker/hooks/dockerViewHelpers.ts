import type {
  DockerComposeProject,
  DockerComposeProjectPayload,
  DockerComposeService,
} from '@/api/docker'

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
    compose: false,
    containers: false,
    images: false,
    networks: false,
    overview: false,
    volumes: false,
  }
}

export function getComposeConfigFiles(project: DockerComposeProject) {
  return project.configFiles
    .split(',')
    .map((file) => file.trim())
    .filter(Boolean)
}

export function getComposeProjectPayload(
  project: DockerComposeProject,
): DockerComposeProjectPayload | null {
  const configFiles = getComposeConfigFiles(project)
  if (!project.name || configFiles.length === 0) {
    return null
  }

  return {
    configFiles,
    projectName: project.name,
    workingDir: project.workingDir || undefined,
  }
}

export function getComposeStatusType(project: DockerComposeProject) {
  const status = project.status.toLowerCase()
  if (status.includes('running')) {
    return 'success'
  }
  if (status.includes('exited') || status.includes('stopped')) {
    return 'warning'
  }
  return 'default'
}

export function getComposeServiceStatusType(service: DockerComposeService) {
  const state = `${service.state} ${service.status}`.toLowerCase()
  if (state.includes('running')) {
    return 'success'
  }
  if (state.includes('exit') || state.includes('stop')) {
    return 'warning'
  }
  return 'default'
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
