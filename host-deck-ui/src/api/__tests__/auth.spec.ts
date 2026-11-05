import { beforeEach, describe, expect, it, vi } from 'vitest'

const { deleteRequest, get, post } = vi.hoisted(() => ({
  deleteRequest: vi.fn(),
  get: vi.fn(),
  post: vi.fn(),
}))

vi.mock('@/lib/http', () => ({
  http: {
    delete: deleteRequest,
    get,
    post,
  },
}))

import { authApi } from '@/api/auth'

describe('authApi', () => {
  beforeEach(() => {
    get.mockReset()
    post.mockReset()
    deleteRequest.mockReset()
  })

  it('creates a saved-server connection without sending stored secrets', async () => {
    post.mockResolvedValue({ data: { connectionId: 'conn-1' } })

    await expect(
      authApi.connect({ host: 'host.example', port: 22, serverId: 12, username: 'deploy' }),
    ).resolves.toEqual({ connectionId: 'conn-1' })

    expect(post).toHaveBeenCalledWith('/api/connect', {
      host: 'host.example',
      port: 22,
      serverId: 12,
      username: 'deploy',
    })
  })

  it('disconnects an explicit connection id', async () => {
    deleteRequest.mockResolvedValue({ data: { success: true } })

    await expect(authApi.disconnect('conn-1')).resolves.toEqual({ success: true })

    expect(deleteRequest).toHaveBeenCalledWith('/api/connect', {
      params: { connectionId: 'conn-1' },
    })
  })

  it('passes a cancellation signal and request id when connecting', async () => {
    post.mockResolvedValue({ data: { connectionId: 'conn-2' } })
    const controller = new AbortController()
    const payload = { host: 'host.example', port: 22, username: 'deploy' }
    await authApi.connect(payload, { requestId: 'request-123', signal: controller.signal })
    expect(post).toHaveBeenCalledWith(
      '/api/connect',
      { ...payload, requestId: 'request-123' },
      { signal: controller.signal },
    )
  })

  it('cancels a pending connection by request id', async () => {
    deleteRequest.mockResolvedValue({ data: { success: true } })
    await authApi.cancelConnect('request-123')
    expect(deleteRequest).toHaveBeenCalledWith('/api/connect/pending', {
      params: { requestId: 'request-123' },
    })
  })
})
