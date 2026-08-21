import { describe, expect, it, vi } from 'vitest'

const { openWindow, warning } = vi.hoisted(() => ({
  openWindow: vi.fn(),
  warning: vi.fn(),
}))

vi.mock('@/api/docker', () => ({ dockerApi: {} }))
vi.mock('@/lib/ui', () => ({
  getUiApi: () => ({
    dialog: { warning },
    message: { error: vi.fn(), success: vi.fn(), warning: vi.fn() },
  }),
}))
vi.mock('@/stores/desktop', () => ({ useDesktopStore: () => ({ openWindow }) }))
vi.mock('@/stores/docker-output', () => ({ useDockerOutputStore: () => ({}) }))
vi.mock('@/stores/ssh', () => ({
  useSshStore: () => ({ connectionId: 'conn-1', host: 'host.example', username: 'deploy' }),
}))
vi.mock('@/stores/upload-center', () => ({ useUploadCenterStore: () => ({}) }))

import { useDockerView } from '../useDockerView'

describe('useDockerView dangerous actions', () => {
  it('requires an explicit confirmation before removing a container', () => {
    warning.mockReset()
    warning.mockReturnValue({ loading: false })
    const controller = useDockerView({ connectionId: 'conn-1', host: 'host.example' })

    controller.confirmContainerAction(
      {
        createdAt: '',
        id: 'container-1',
        image: 'nginx:latest',
        name: 'web',
        networks: [],
        ports: [],
        state: 'running',
        status: 'Up',
      },
      'remove',
    )

    expect(warning).toHaveBeenCalledWith(
      expect.objectContaining({
        content: '确认删除容器 web？',
        negativeText: '取消',
        positiveText: '删除',
        title: '删除容器',
      }),
    )
  })

  it('opens the existing SSH terminal for a running container', async () => {
    openWindow.mockReset()
    const controller = useDockerView({
      connectionId: 'conn-1',
      host: 'host.example',
      username: 'deploy',
      windowId: 'docker-window',
    })

    await controller.enterShell({
      createdAt: '',
      id: 'container-1',
      image: 'nginx:latest',
      name: 'web',
      networks: [],
      ports: [],
      state: 'running',
      status: 'Up',
    })

    expect(openWindow).toHaveBeenCalledWith(
      'terminal',
      {
        connectionId: 'conn-1',
        host: 'host.example',
        startupCommand: 'docker exec -it container-1 bash || docker exec -it container-1 sh',
        title: 'Shell · web',
        username: 'deploy',
      },
      {
        maximizable: false,
        parentId: 'docker-window',
        resizable: false,
      },
    )
  })

  it('opens the container form in edit mode for a stopped container', () => {
    openWindow.mockReset()
    const controller = useDockerView({
      connectionId: 'conn-1',
      host: 'host.example',
      username: 'deploy',
      windowId: 'docker-window',
    })

    controller.openEditContainer({
      createdAt: '',
      id: 'container-1',
      image: 'nginx:latest',
      name: 'web',
      networks: [],
      ports: [],
      state: 'exited',
      status: 'Exited',
    })

    expect(openWindow).toHaveBeenCalledWith(
      'docker-create-container',
      {
        connectionId: 'conn-1',
        containerId: 'container-1',
        host: 'host.example',
        title: '编辑容器 · web',
        username: 'deploy',
      },
      {
        maximizable: false,
        parentId: 'docker-window',
        resizable: false,
      },
    )
  })
})

describe('useDockerView container windows', () => {
  const container = {
    createdAt: '',
    id: 'container-1',
    image: 'nginx:latest',
    name: 'web',
    networks: [],
    ports: [],
    state: 'running',
    status: 'Up',
  }

  it('opens a child log window', () => {
    openWindow.mockReset()
    const controller = useDockerView({ connectionId: 'conn-1', windowId: 'docker-window' })

    controller.viewLogs(container)

    expect(openWindow).toHaveBeenCalledWith(
      'docker-container-logs',
      {
        connectionId: 'conn-1',
        containerId: 'container-1',
        containerName: 'web',
        title: '容器日志 · web',
      },
      {
        maximizable: false,
        parentId: 'docker-window',
        resizable: false,
      },
    )
  })

  it('opens a child resource monitoring window', () => {
    openWindow.mockReset()
    const controller = useDockerView({ connectionId: 'conn-1', windowId: 'docker-window' })
    controller.viewStats(container)

    expect(openWindow).toHaveBeenCalledWith(
      'docker-container-stats',
      {
        connectionId: 'conn-1',
        containerId: 'container-1',
        containerName: 'web',
        title: '资源监控 · web',
      },
      {
        maximizable: false,
        parentId: 'docker-window',
        resizable: false,
      },
    )
  })

  it('opens a child image pull window', () => {
    openWindow.mockReset()
    const controller = useDockerView({ connectionId: 'conn-1', windowId: 'docker-window' })

    controller.openPullImageDialog()

    expect(openWindow).toHaveBeenCalledWith(
      'docker-image-pull',
      {
        connectionId: 'conn-1',
        title: '拉取镜像',
      },
      {
        maximizable: false,
        parentId: 'docker-window',
        resizable: false,
      },
    )
  })
})
