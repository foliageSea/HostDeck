import type {
  DockerContainer,
  DockerComposeProject,
  DockerComposeProjectPayload,
  DockerComposeService,
} from '@/api/docker'
import type { DockerTabName } from './dockerViewTypes'

export type DockerStatusTagType = 'default' | 'error' | 'info' | 'success' | 'warning'

export interface DockerStatusPresentation {
  label: string
  description: string
  type: DockerStatusTagType
}

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
  return { configFiles, projectName: project.name, workingDir: project.workingDir || undefined }
}

export function getComposeStatusType(project: DockerComposeProject) {
  return getComposeStatusPresentation(project).type
}

export function getContainerStatusPresentation(
  container: DockerContainer,
): DockerStatusPresentation {
  const state = container.state.trim().toLowerCase()
  const status = container.status.trim()
  const normalizedStatus = status.toLowerCase()

  if (normalizedStatus.includes('unhealthy')) {
    return {
      label: '运行异常',
      description: '容器正在运行，但健康检查未通过。',
      type: 'error',
    }
  }
  if (normalizedStatus.includes('health: starting')) {
    return {
      label: '健康检查中',
      description: '容器正在运行，健康检查尚未完成。',
      type: 'warning',
    }
  }
  if (normalizedStatus.includes('paused') || state === 'paused') {
    return { label: '已暂停', description: '容器进程已暂停，可执行恢复操作。', type: 'warning' }
  }
  if (state === 'restarting' || normalizedStatus.includes('restarting')) {
    return { label: '重启中', description: '容器正在自动重启。', type: 'warning' }
  }
  if (state === 'running') {
    return { label: '运行中', description: '容器当前正在运行。', type: 'success' }
  }
  if (state === 'created') {
    return { label: '已创建', description: '容器已创建，但尚未启动。', type: 'info' }
  }
  if (state === 'exited' || normalizedStatus.includes('exited')) {
    return { label: '已退出', description: '容器进程已退出。', type: 'default' }
  }
  if (state === 'dead') {
    return { label: '异常停止', description: '容器无法正常清理或启动，需要检查。', type: 'error' }
  }
  if (state === 'removing') {
    return { label: '删除中', description: '容器正在被删除。', type: 'warning' }
  }

  return { label: '状态未知', description: 'Docker 返回了未识别的容器状态。', type: 'default' }
}

export function getComposeStatusPresentation(
  project: DockerComposeProject,
): DockerStatusPresentation {
  const status = project.status.trim()
  const normalizedStatus = status.toLowerCase()
  const running = normalizedStatus.includes('running')
  const stopped = normalizedStatus.includes('exited') || normalizedStatus.includes('stopped')

  if (running && stopped) {
    return {
      label: '部分运行',
      description: '编排中同时存在运行和已停止的服务。',
      type: 'warning',
    }
  }
  if (normalizedStatus.includes('restarting')) {
    return { label: '重启中', description: '编排中有服务正在重启。', type: 'warning' }
  }
  if (running) {
    return { label: '运行中', description: '编排中的服务正在运行。', type: 'success' }
  }
  if (stopped) {
    return { label: '已停止', description: '编排当前没有运行中的服务。', type: 'default' }
  }
  if (normalizedStatus.includes('created')) {
    return { label: '已创建', description: '编排已创建，但服务尚未启动。', type: 'info' }
  }

  return {
    label: '状态未知',
    description: 'Docker Compose 返回了未识别的项目状态。',
    type: 'default',
  }
}

export function getComposeServiceStatusPresentation(
  service: DockerComposeService,
): DockerStatusPresentation {
  const state = service.state.trim().toLowerCase()
  const status = service.status.trim().toLowerCase()
  const combined = `${state} ${status}`

  if (combined.includes('unhealthy')) {
    return {
      label: '运行异常',
      description: '服务容器正在运行，但健康检查未通过。',
      type: 'error',
    }
  }
  if (combined.includes('health: starting')) {
    return {
      label: '健康检查中',
      description: '服务容器正在运行，健康检查尚未完成。',
      type: 'warning',
    }
  }
  if (combined.includes('paused')) {
    return { label: '已暂停', description: '服务容器进程已暂停。', type: 'warning' }
  }
  if (combined.includes('restarting')) {
    return { label: '重启中', description: '服务容器正在自动重启。', type: 'warning' }
  }
  if (combined.includes('running') || combined.includes('up')) {
    return { label: '运行中', description: '服务容器当前正在运行。', type: 'success' }
  }
  if (combined.includes('created')) {
    return { label: '已创建', description: '服务容器已创建，但尚未启动。', type: 'info' }
  }
  if (combined.includes('exit') || combined.includes('stop')) {
    return { label: '已停止', description: '服务容器当前未运行。', type: 'default' }
  }
  if (combined.includes('dead')) {
    return { label: '异常停止', description: '服务容器需要检查或手动清理。', type: 'error' }
  }

  return {
    label: '状态未知',
    description: 'Docker Compose 返回了未识别的服务状态。',
    type: 'default',
  }
}

export function getComposeServiceStatusType(service: DockerComposeService) {
  return getComposeServiceStatusPresentation(service).type
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
