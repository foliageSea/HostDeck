import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { FileTask, FileTaskStatus } from '@/api/files'

const { error, success, warning } = vi.hoisted(() => ({
  error: vi.fn(),
  success: vi.fn(),
  warning: vi.fn(),
}))

vi.mock('@/lib/ui', () => ({
  getUiApi: () => ({ notification: { error, success, warning } }),
}))

import { useUploadCenterStore } from '../upload-center'

function createTask(status: FileTaskStatus, id = `task-${status}`): FileTask {
  return {
    connectionId: 'connection-1',
    createdAt: 1,
    errorMessage: status === 'failed' ? '远端命令执行失败。' : null,
    finishedAt: status === 'queued' || status === 'running' ? null : 2,
    id,
    items: [
      {
        errorMessage: null,
        id: 1,
        sourcePath: '/var/backups/app.tar.gz',
        status,
        targetPath: '/var/backups/app',
      },
    ],
    startedAt: status === 'queued' ? null : 1,
    status,
    type: 'extract',
  }
}

describe('upload center remote task notifications', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    error.mockReset()
    success.mockReset()
    warning.mockReset()
  })

  it('notifies once when a remote task succeeds', () => {
    const store = useUploadCenterStore()
    const task = createTask('success')

    store.upsertRemoteTask(task)
    store.upsertRemoteTask(task)

    expect(success).toHaveBeenCalledOnce()
    expect(success).toHaveBeenCalledWith({
      title: '解压任务已完成',
      content: '/var/backups/app.tar.gz',
      duration: 5000,
    })
  })

  it('uses error and warning notifications for failed and cancelled tasks', () => {
    const store = useUploadCenterStore()

    store.upsertRemoteTask(createTask('failed'))
    store.upsertRemoteTask(createTask('cancelled'))

    expect(error).toHaveBeenCalledWith({
      title: '解压任务失败',
      content: '远端命令执行失败。',
      duration: 8000,
    })
    expect(warning).toHaveBeenCalledWith({
      title: '解压任务已取消',
      content: '/var/backups/app.tar.gz',
      duration: 5000,
    })
  })

  it('does not notify while restoring task history', () => {
    const store = useUploadCenterStore()

    store.upsertRemoteTask(createTask('success'), { notify: false })

    expect(success).not.toHaveBeenCalled()
    expect(error).not.toHaveBeenCalled()
    expect(warning).not.toHaveBeenCalled()
  })
})
