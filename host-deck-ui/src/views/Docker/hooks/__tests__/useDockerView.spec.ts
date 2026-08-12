import { nextTick } from 'vue'
import { describe, expect, it, vi } from 'vitest'

const { openWindow, streamContainerLogs, warning } = vi.hoisted(() => ({
  openWindow: vi.fn(),
  streamContainerLogs: vi.fn(),
  warning: vi.fn(),
}))

vi.mock('@/api/docker', () => ({ dockerApi: { streamContainerLogs } }))
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

    expect(openWindow).toHaveBeenCalledWith('terminal', {
      connectionId: 'conn-1',
      host: 'host.example',
      startupCommand: 'docker exec -it container-1 bash || docker exec -it container-1 sh',
      title: 'Shell · web',
      username: 'deploy',
    })
  })
})

describe('useDockerView container logs', () => {
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

  it('appends streamed logs and marks the stream as ended', async () => {
    streamContainerLogs.mockReset()
    streamContainerLogs.mockImplementation(
      async (
        _connectionId: string,
        _containerId: string,
        _options: unknown,
        onEvent: (event: { event: string; data: Record<string, string> }) => void,
      ) => {
        onEvent({ event: 'connected', data: {} })
        onEvent({ event: 'stdout', data: { text: 'hello\n' } })
        onEvent({ event: 'stderr', data: { text: 'error\n' } })
        onEvent({ event: 'done', data: {} })
      },
    )
    const controller = useDockerView({ connectionId: 'conn-1' })

    await controller.viewLogs(container)

    expect(controller.displayedLogs.value).toBe('hello\nerror\n')
    expect(controller.logsStreamStatus.value).toBe('ended')
    expect(streamContainerLogs).toHaveBeenCalledWith(
      'conn-1',
      'container-1',
      { tail: 200, timestamps: true },
      expect.any(Function),
      expect.any(AbortSignal),
    )
  })

  it('aborts the stream when the log modal closes', async () => {
    streamContainerLogs.mockReset()
    let signal: AbortSignal | undefined
    streamContainerLogs.mockImplementation(
      async (
        _connectionId: string,
        _containerId: string,
        _options: unknown,
        _onEvent: unknown,
        requestSignal: AbortSignal,
      ) => {
        signal = requestSignal
        await new Promise<void>((resolve) =>
          requestSignal.addEventListener('abort', () => resolve()),
        )
      },
    )
    const controller = useDockerView({ connectionId: 'conn-1' })
    const pending = controller.viewLogs(container)

    await nextTick()
    controller.logsVisible.value = false
    await nextTick()
    await pending

    expect(signal?.aborted).toBe(true)
  })
})
