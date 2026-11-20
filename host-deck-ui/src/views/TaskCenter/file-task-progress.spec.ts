import { describe, expect, it } from 'vitest'
import type { FileTask, FileTaskProgress, FileTaskStatus } from '@/api/files'
import { getRemoteTaskProgress } from './file-task-progress'

type FileTaskItem = FileTask['items'][number]

function item(
  id: number,
  status: FileTaskStatus,
  progress?: FileTaskProgress | null,
): FileTaskItem {
  return { id, status, sourcePath: '/item-' + id, progress }
}

function progress(fields: Partial<FileTaskProgress> = {}): FileTaskProgress {
  return {
    phase: 'working',
    bytesDone: 0,
    bytesTotal: null,
    entriesDone: 0,
    entriesTotal: null,
    ...fields,
  }
}

function task(status: FileTaskStatus, ...items: FileTaskItem[]): FileTask {
  return { status, items, id: 'task', connectionId: 'connection', createdAt: 0, type: 'move' }
}

describe('remote task progress presentation', () => {
  it.each(['running', 'failed', 'cancelled'] as const)(
    'does not assume a mode for a %s item without confirmed execution',
    (status) => {
      const deploying = item(1, status, progress({ phase: 'deploying' }))
      const noProgress = item(2, status, null)
      expect(getRemoteTaskProgress(task(status, deploying, noProgress)).modeLabels).toEqual([])
    },
  )

  it('shows SideCar mode once remote scanning starts', () => {
    const scanning = item(1, 'running', progress({ phase: 'scanning' }))
    expect(getRemoteTaskProgress(task('running', scanning)).modeLabels).toEqual(['SideCar 模式'])
  })

  it('shows compatibility mode after fallback, including on completed tasks', () => {
    const legacy = progress({ phase: 'legacy' })
    for (const status of ['running', 'success'] as const) {
      expect(getRemoteTaskProgress(task(status, item(1, status, legacy))).modeLabels).toEqual([
        '兼容模式',
      ])
    }
  })

  it('recognizes SideCar success even when no progress arrived after deployment', () => {
    const done = item(1, 'success', progress({ phase: 'deploying' }))
    expect(getRemoteTaskProgress(task('success', done)).modeLabels).toEqual(['SideCar 模式'])
  })

  it('shows both modes only once in a mixed batch, including finished items', () => {
    const legacy = item(1, 'success', progress({ phase: 'legacy' }))
    const sidecar = item(2, 'failed', progress({ phase: 'committing' }))
    const other = item(3, 'success', progress())
    const cancelled = item(4, 'cancelled')
    expect(
      getRemoteTaskProgress(task('failed', legacy, sidecar, other, cancelled)).modeLabels,
    ).toEqual(['SideCar 模式', '兼容模式'])
  })

  it('does not report a false percentage for old or unmeasurable tasks', () => {
    for (const value of [
      undefined,
      null,
      progress(),
      progress({ bytesTotal: 0, entriesTotal: 0 }),
    ]) {
      expect(
        getRemoteTaskProgress(task('running', item(1, 'running', value))).percentage,
      ).toBeNull()
    }
  })

  it('shows processed counts even when the archive total is unknown', () => {
    const value = progress({ bytesDone: 2 * 1024 ** 2, entriesDone: 3 })
    expect(getRemoteTaskProgress(task('running', item(1, 'running', value)))).toMatchObject({
      percentage: null,
      currentPercentage: null,
      processed: '2 MiB · 3 个条目',
    })
  })

  it.each([
    ['deploying', '正在部署远端助手'],
    ['scanning', '正在扫描文件'],
    ['legacy', '兼容模式处理中'],
  ] as const)('does not show a percentage during %s', (phase, phaseLabel) => {
    const value = progress({ phase, bytesTotal: 10, entriesTotal: 1 })
    expect(getRemoteTaskProgress(task('running', item(1, 'running', value)))).toMatchObject({
      percentage: null,
      phaseLabel,
    })
  })

  it.each(['running', 'failed', 'cancelled'] as const)(
    'never rounds a %s task up to 100%%',
    (status) => {
      const value = progress({ phase: 'committing', bytesDone: 10, bytesTotal: 10 })
      expect(getRemoteTaskProgress(task(status, item(1, status, value))).percentage).toBe(99)
    },
  )

  it('shows the source-removal phase and reports 100 only after overall success', () => {
    const value = progress({
      phase: 'removingSource',
      bytesTotal: 0,
      entriesDone: 1,
      entriesTotal: 1,
    })
    expect(getRemoteTaskProgress(task('running', item(1, 'running', value)))).toMatchObject({
      percentage: 99,
      phaseLabel: '正在删除源文件',
    })
    expect(getRemoteTaskProgress(task('success', item(1, 'success', null))).percentage).toBe(100)
  })

  it('does not show overall success while completed items are still being finalized', () => {
    const done = item(1, 'success', progress({ bytesDone: 10, bytesTotal: 10 }))
    expect(getRemoteTaskProgress(task('running', done))).toMatchObject({
      percentage: 99,
      phaseLabel: '正在收尾',
    })
  })

  it('aggregates comparable totals without averaging percentages', () => {
    const large = item(1, 'success', progress({ bytesTotal: 90 }))
    const small = item(2, 'running', progress({ bytesDone: 5, bytesTotal: 10 }))
    expect(getRemoteTaskProgress(task('running', large, small)).percentage).toBe(95)
  })

  it('falls back to completed item count and current item for mixed or missing units', () => {
    const done = item(1, 'success', progress({ bytesTotal: 90 }))
    for (const value of [null, progress({ entriesDone: 4, entriesTotal: 5 })]) {
      const current = item(2, 'running', value)
      expect(getRemoteTaskProgress(task('running', done, current))).toMatchObject({
        percentage: null,
        completed: 1,
        total: 2,
        currentPath: '/item-2',
      })
    }
  })
})
