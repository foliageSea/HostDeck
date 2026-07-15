import { beforeEach, describe, expect, it, vi } from 'vitest'

const { post } = vi.hoisted(() => ({ post: vi.fn() }))

vi.mock('@/lib/http', () => ({
  http: { post },
}))

import { filesApi } from '@/api/files'

describe('filesApi', () => {
  beforeEach(() => {
    post.mockReset()
  })

  it('writes plain text with the target connection and path', async () => {
    post.mockResolvedValue({ data: { success: true } })

    await expect(filesApi.writeFile('conn-1', '/etc/app.conf', 'enabled=true\n')).resolves.toEqual({
      success: true,
    })

    expect(post).toHaveBeenCalledWith('/api/files/write', 'enabled=true\n', {
      headers: { 'Content-Type': 'text/plain' },
      params: { connectionId: 'conn-1', path: '/etc/app.conf' },
    })
  })
})
