import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { useDockerOutputStore } from '@/stores/docker-output'

describe('docker output store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('collects output and completes a task', async () => {
    const store = useDockerOutputStore()
    const taskId = store.createTask('connection-1', '拉取镜像')

    await expect(
      store.runTask(taskId, async ({ append }) => {
        append('Downloading\n')
        return 'done'
      }),
    ).resolves.toBe('done')

    expect(store.findTask(taskId)).toMatchObject({
      output: 'Downloading\n',
      status: 'success',
    })
  })

  it('aborts and marks a running task as cancelled', async () => {
    const store = useDockerOutputStore()
    const taskId = store.createTask('connection-1', '拉取镜像')
    const promise = store.runTask(
      taskId,
      ({ signal }) =>
        new Promise((_resolve, reject) => {
          signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')))
        }),
    )

    store.cancelTask(taskId)

    await expect(promise).rejects.toMatchObject({ name: 'AbortError' })
    expect(store.findTask(taskId)?.status).toBe('cancelled')
  })

  it('cancels and waits for running tasks from one connection', async () => {
    const store = useDockerOutputStore()
    const firstTaskId = store.createTask('connection-1', '启动编排')
    const secondTaskId = store.createTask('connection-2', '停止编排')
    const runUntilAborted = (taskId: string) =>
      store.runTask(
        taskId,
        ({ signal }) =>
          new Promise((_resolve, reject) => {
            signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')))
          }),
      )
    const firstRun = runUntilAborted(firstTaskId)
    const secondRun = runUntilAborted(secondTaskId)

    await store.cancelTasksByConnection('connection-1')

    await expect(firstRun).rejects.toMatchObject({ name: 'AbortError' })
    expect(store.findTask(firstTaskId)?.status).toBe('cancelled')
    expect(store.findTask(secondTaskId)?.status).toBe('running')
    store.cancelTask(secondTaskId)
    await expect(secondRun).rejects.toMatchObject({ name: 'AbortError' })
  })

  it('limits retained output size', () => {
    const store = useDockerOutputStore()
    const taskId = store.createTask('connection-1', '拉取镜像')

    store.appendOutput(taskId, 'x'.repeat(600 * 1024))

    const output = store.findTask(taskId)?.output ?? ''
    expect(output.startsWith('[较早的输出已截断]\n')).toBe(true)
    expect(output.length).toBeLessThan(513 * 1024)
  })
})
