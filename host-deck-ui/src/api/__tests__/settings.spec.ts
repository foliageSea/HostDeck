import { beforeEach, describe, expect, it, vi } from 'vitest'

const { get } = vi.hoisted(() => ({ get: vi.fn() }))

vi.mock('@/lib/http', () => ({
  http: { get },
}))

import { settingsApi } from '@/api/settings'

describe('settingsApi', () => {
  beforeEach(() => {
    get.mockReset()
  })

  it('downloads the log archive as a blob', async () => {
    const archive = new Blob(['logs'], { type: 'application/zip' })
    get.mockResolvedValue({ data: archive })

    await expect(settingsApi.exportLogs()).resolves.toBe(archive)
    expect(get).toHaveBeenCalledWith('/api/settings/logs/export', {
      responseType: 'blob',
    })
  })
})
