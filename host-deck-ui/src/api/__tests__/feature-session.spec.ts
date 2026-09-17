import { afterEach, describe, expect, it, vi } from 'vitest'
import { cronTaskApi } from '@/api/cron-task'
import { dockerApi } from '@/api/docker'
import { processApi } from '@/api/process'
import { http } from '@/lib/http'

afterEach(() => {
  vi.restoreAllMocks()
})

describe('feature session cleanup', () => {
  it('closes shared feature sessions by connection', async () => {
    const remove = vi.spyOn(http, 'delete').mockResolvedValue({ data: { success: true } })

    await processApi.closeSession('connection-1')
    await cronTaskApi.closeSession('connection-2')
    await dockerApi.closeComposeSession('connection-3')

    expect(remove).toHaveBeenNthCalledWith(1, '/api/processes/session', {
      params: { connectionId: 'connection-1' },
    })
    expect(remove).toHaveBeenNthCalledWith(2, '/api/cron-tasks/session', {
      params: { connectionId: 'connection-2' },
    })
    expect(remove).toHaveBeenNthCalledWith(3, '/api/docker/compose/session', {
      params: { connectionId: 'connection-3' },
    })
  })
})
