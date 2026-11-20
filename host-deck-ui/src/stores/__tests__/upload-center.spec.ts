import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { FileTask, FileTaskStatus } from '@/api/files'

const { cancelTask, error, listTasks, success, warning, watchTask } = vi.hoisted(() => ({
  cancelTask: vi.fn<(taskId: string) => Promise<FileTask>>(),
  error: vi.fn(),
  listTasks: vi.fn<(connectionId: string) => Promise<FileTask[]>>(),
  success: vi.fn(),
  warning: vi.fn(),
  watchTask:
    vi.fn<
      (taskId: string, onTask: (task: FileTask) => void, signal: AbortSignal) => Promise<void>
    >(),
}))

vi.mock('@/api/files', () => ({ filesApi: { cancelTask, listTasks, watchTask } }))

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

function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>((resolvePromise) => {
    resolve = resolvePromise
  })
  return { promise, resolve }
}

beforeEach(() => {
  vi.useFakeTimers()
  setActivePinia(createPinia())
  vi.resetAllMocks()
  watchTask.mockImplementation(
    (_taskId, _onTask, signal) =>
      new Promise((resolve) => signal.addEventListener('abort', () => resolve(), { once: true })),
  )
})

afterEach(() => {
  useUploadCenterStore().$dispose()
  vi.useRealTimers()
})

describe('upload center remote task notifications', () => {
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

describe('shared remote file task watches', () => {
  it('watches once and updates after the Files refresh listener detaches', () => {
    const store = useUploadCenterStore()
    const closedWindowRefresh = vi.fn()
    const openWindowRefresh = vi.fn()
    const detach = store.onRemoteTaskCompleted(closedWindowRefresh)
    store.onRemoteTaskCompleted(openWindowRefresh)
    store.upsertRemoteTask(createTask('queued', 'shared'), { windowId: 'original-window' })
    store.upsertRemoteTask(createTask('queued', 'shared'))
    expect(watchTask).toHaveBeenCalledOnce()
    const [, onTask, signal] = watchTask.mock.calls[0]!
    detach()
    expect(signal.aborted).toBe(false)

    const terminal = createTask('success', 'shared')
    onTask(terminal)
    onTask(terminal)

    expect(store.batches[0]?.remoteTask?.status).toBe('success')
    expect(signal.aborted).toBe(true)
    expect(closedWindowRefresh).not.toHaveBeenCalled()
    expect(openWindowRefresh).toHaveBeenCalledExactlyOnceWith(terminal, 'original-window')
    expect(success).toHaveBeenCalledOnce()
  })

  it('reconnects with exponential backoff after both transport errors and EOF', async () => {
    const store = useUploadCenterStore()
    watchTask.mockRejectedValueOnce(new Error('offline')).mockImplementationOnce((_id, onTask) => {
      onTask(createTask('running', 'retry'))
      return Promise.resolve()
    })
    store.upsertRemoteTask(createTask('queued', 'retry'))
    await vi.advanceTimersByTimeAsync(999)
    expect(watchTask).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(1)
    expect(watchTask).toHaveBeenCalledTimes(2)
    await vi.advanceTimersByTimeAsync(1999)
    expect(watchTask).toHaveBeenCalledTimes(2)
    await vi.advanceTimersByTimeAsync(1)
    expect(watchTask).toHaveBeenCalledTimes(3)

    watchTask.mock.calls[2]![1](createTask('success', 'retry'))
    await vi.advanceTimersByTimeAsync(60_000)
    expect(watchTask).toHaveBeenCalledTimes(3)
  })

  it('ignores older active history and cancel responses after terminal SSE', async () => {
    const store = useUploadCenterStore()
    const history = deferred<FileTask[]>()
    const cancellation = deferred<FileTask>()
    listTasks.mockReturnValueOnce(history.promise)
    cancelTask.mockReturnValueOnce(cancellation.promise)
    const restoring = store.restoreRemoteTasks('connection-1')
    store.upsertRemoteTask(createTask('running', 'race'))
    store.cancelBatch('race')
    store.cancelBatch('race')
    expect(cancelTask).toHaveBeenCalledExactlyOnceWith('race')
    watchTask.mock.calls[0]![1](createTask('success', 'race'))
    history.resolve([createTask('running', 'race')])
    cancellation.resolve(createTask('queued', 'race'))
    await restoring

    expect(store.batches[0]?.remoteTask?.status).toBe('success')
    expect(watchTask).toHaveBeenCalledOnce()
    expect(success).toHaveBeenCalledOnce()
    expect(warning).not.toHaveBeenCalled()
  })

  it('keeps live progress when active history arrives but handles a known terminal transition', async () => {
    const store = useUploadCenterStore()
    const running = createTask('running', 'restore')
    running.items[0]!.progress = {
      phase: 'scanning',
      bytesDone: 42,
      bytesTotal: null,
      entriesDone: 3,
      entriesTotal: null,
    }
    store.upsertRemoteTask(running)
    listTasks.mockResolvedValueOnce([createTask('running', 'restore')])
    await store.restoreRemoteTasks('connection-1')
    expect(store.batches[0]?.remoteTask?.items[0]?.progress).toEqual(running.items[0]!.progress)

    const refresh = vi.fn()
    store.onRemoteTaskCompleted(refresh)
    listTasks.mockResolvedValueOnce([createTask('cancelled', 'restore')])
    await store.restoreRemoteTasks('connection-1')
    expect(watchTask.mock.calls[0]![2].aborted).toBe(true)
    expect(warning).toHaveBeenCalledOnce()
    expect(refresh).toHaveBeenCalledOnce()
  })

  it('keeps an active remote batch until the overall task reaches a terminal state', () => {
    const store = useUploadCenterStore()
    const task = createTask('running', 'finalizing')
    task.items[0]!.status = 'success'
    store.upsertRemoteTask(task)
    expect(store.activeTaskCount).toBe(1)
    store.clearFinished()
    expect(store.batches).toHaveLength(1)

    const failed = createTask('failed', 'finalizing')
    failed.items[0]!.status = 'queued'
    watchTask.mock.calls[0]![1](failed)
    expect(store.activeTaskCount).toBe(0)
    store.clearFinished()
    expect(store.batches).toHaveLength(0)
  })

  it('prefers the failed item error in the task record and notification', () => {
    const store = useUploadCenterStore()
    const failed = createTask('failed')
    failed.items[0]!.errorMessage = '目标文件不可写。'
    store.upsertRemoteTask(failed)
    expect(store.batches[0]?.errorMessage).toBe('目标文件不可写。')
    expect(error).toHaveBeenCalledWith(expect.objectContaining({ content: '目标文件不可写。' }))
  })

  it('stops pending retry on clear and does not resurrect dismissed records', async () => {
    const store = useUploadCenterStore()
    watchTask.mockResolvedValueOnce(undefined)
    cancelTask.mockResolvedValueOnce(createTask('cancelled', 'clear-me'))
    store.upsertRemoteTask(createTask('running', 'clear-me'))
    await vi.advanceTimersByTimeAsync(1)
    store.clearAll()
    await vi.advanceTimersByTimeAsync(60_000)
    listTasks.mockResolvedValueOnce([createTask('running', 'clear-me')])
    await store.restoreRemoteTasks('connection-1')
    expect(cancelTask).toHaveBeenCalledExactlyOnceWith('clear-me')
    expect(watchTask).toHaveBeenCalledOnce()
    expect(store.batches).toHaveLength(0)
  })

  it('aborts an in-flight stream and ignores history started before a clear', async () => {
    const store = useUploadCenterStore()
    const history = deferred<FileTask[]>()
    listTasks.mockReturnValueOnce(history.promise)
    cancelTask.mockResolvedValueOnce(createTask('cancelled', 'clear-stream'))
    const restoring = store.restoreRemoteTasks('connection-1')
    store.upsertRemoteTask(createTask('running', 'clear-stream'))
    const [, onTask, signal] = watchTask.mock.calls[0]!
    store.clearAll()
    expect(signal.aborted).toBe(true)
    onTask(createTask('cancelled', 'clear-stream'))
    history.resolve([createTask('running', 'unknown-at-clear')])
    await restoring
    expect(store.batches).toHaveLength(0)
    expect(watchTask).toHaveBeenCalledOnce()
  })
})
