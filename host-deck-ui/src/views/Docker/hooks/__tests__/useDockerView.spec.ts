import { describe, expect, it, vi } from 'vitest'

const { warning } = vi.hoisted(() => ({ warning: vi.fn() }))

vi.mock('@/api/docker', () => ({ dockerApi: {} }))
vi.mock('@/lib/ui', () => ({
  getUiApi: () => ({
    dialog: { warning },
    message: { error: vi.fn(), success: vi.fn(), warning: vi.fn() },
  }),
}))
vi.mock('@/stores/desktop', () => ({ useDesktopStore: () => ({ openWindow: vi.fn() }) }))
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
})
