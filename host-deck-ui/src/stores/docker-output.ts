import { ref } from 'vue'
import { defineStore } from 'pinia'

export type DockerOutputTaskStatus = 'running' | 'success' | 'error' | 'cancelled'

export interface DockerOutputTask {
  connectionId: string
  createdAt: number
  errorMessage: string
  finishedAt: number | null
  id: string
  output: string
  status: DockerOutputTaskStatus
  title: string
}

interface DockerOutputTaskContext {
  append: (text: string) => void
  signal: AbortSignal
}

const maxOutputLength = 512 * 1024
const maxRetainedTasks = 20

export const useDockerOutputStore = defineStore('docker-output', () => {
  const tasks = ref<DockerOutputTask[]>([])
  const controllers = new Map<string, AbortController>()

  function findTask(taskId: string) {
    return tasks.value.find((task) => task.id === taskId) ?? null
  }

  function createTask(connectionId: string, title: string) {
    const taskId = `docker-output-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
    tasks.value.unshift({
      connectionId,
      createdAt: Date.now(),
      errorMessage: '',
      finishedAt: null,
      id: taskId,
      output: '',
      status: 'running',
      title,
    })

    trimFinishedTasks()
    return taskId
  }

  function trimFinishedTasks() {
    const retained = tasks.value.slice(0, maxRetainedTasks)
    const active = tasks.value.slice(maxRetainedTasks).filter((task) => task.status === 'running')
    tasks.value = [...retained, ...active]
  }

  function appendOutput(taskId: string, text: string) {
    const task = findTask(taskId)
    if (!task || !text) {
      return
    }

    task.output += text
    if (task.output.length > maxOutputLength) {
      task.output = `[较早的输出已截断]\n${task.output.slice(-maxOutputLength)}`
    }
  }

  async function runTask<T>(
    taskId: string,
    runner: (context: DockerOutputTaskContext) => Promise<T>,
  ) {
    const task = findTask(taskId)
    if (!task) {
      throw new Error('Docker 输出任务不存在。')
    }

    const controller = new AbortController()
    controllers.get(taskId)?.abort()
    controllers.set(taskId, controller)

    try {
      const result = await runner({
        append: (text) => appendOutput(taskId, text),
        signal: controller.signal,
      })
      task.status = 'success'
      task.finishedAt = Date.now()
      return result
    } catch (error) {
      if (controller.signal.aborted) {
        task.status = 'cancelled'
        task.errorMessage = '操作已停止。'
      } else {
        task.status = 'error'
        task.errorMessage = error instanceof Error ? error.message : 'Docker 操作失败。'
      }
      task.finishedAt = Date.now()
      throw error
    } finally {
      if (controllers.get(taskId) === controller) {
        controllers.delete(taskId)
      }
      trimFinishedTasks()
    }
  }

  function cancelTask(taskId: string) {
    const task = findTask(taskId)
    if (!task || task.status !== 'running') {
      return
    }
    controllers.get(taskId)?.abort()
  }

  return {
    appendOutput,
    cancelTask,
    createTask,
    findTask,
    runTask,
    tasks,
  }
})
