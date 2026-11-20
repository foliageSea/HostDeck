import type { FileTask, FileTaskProgress } from '@/api/files'

const phaseLabels: Record<FileTaskProgress['phase'], string> = {
  deploying: '正在部署远端助手',
  scanning: '正在扫描文件',
  working: '正在处理文件',
  committing: '正在提交结果',
  removingSource: '正在删除源文件',
  legacy: '兼容模式处理中',
}

function getMeasurement(progress?: FileTaskProgress | null) {
  if (!progress || ['deploying', 'scanning', 'legacy'].includes(progress.phase)) return null

  if (progress.bytesTotal !== null && progress.bytesTotal > 0) {
    return { unit: 'bytes', done: progress.bytesDone, total: progress.bytesTotal }
  }
  if (progress.bytesTotal === 0 && progress.entriesTotal !== null && progress.entriesTotal > 0) {
    return { unit: 'entries', done: progress.entriesDone, total: progress.entriesTotal }
  }
  return null
}

function formatMeasuredBytes(bytes: number) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB']
  let unit = 0
  while (bytes >= 1024 && unit < units.length - 1) {
    bytes /= 1024
    unit++
  }
  return bytes.toLocaleString('zh-CN', { maximumFractionDigits: 1 }) + ' ' + units[unit]
}

export function getRemoteTaskProgress(task: FileTask) {
  const current =
    task.status === 'running'
      ? (task.items.find((item) => item.status === 'running') ??
        task.items.find((item) => item.status === 'queued'))
      : undefined
  const progress = current?.progress
  const measurement = getMeasurement(progress)
  const processed =
    progress?.phase === 'working'
      ? [
          progress.bytesDone > 0 ? formatMeasuredBytes(progress.bytesDone) : null,
          progress.entriesDone > 0 ? String(progress.entriesDone) + ' 个条目' : null,
        ]
          .filter(Boolean)
          .join(' · ')
      : ''
  const presentation = {
    percentage: null as number | null,
    currentPercentage: measurement
      ? Math.min(99, Math.round((measurement.done / measurement.total) * 100))
      : null,
    processed,
    completed: task.items.filter((item) => item.status === 'success').length,
    total: task.items.length,
    currentPath: current?.sourcePath,
    phaseLabel: current?.progress
      ? phaseLabels[current.progress.phase]
      : task.status === 'running' && !current && task.items.length > 0
        ? '正在收尾'
        : undefined,
  }

  if (task.status === 'success') return { ...presentation, percentage: 100 }

  let unit: string | undefined
  let total = 0
  let done = 0
  for (const item of task.items) {
    const measurement = getMeasurement(item.progress)
    if (!measurement || (unit && measurement.unit !== unit)) return presentation
    unit = measurement.unit
    total += measurement.total
    done +=
      item.status === 'success'
        ? measurement.total
        : Math.min(measurement.total, Math.max(0, measurement.done))
  }

  if (total > 0) presentation.percentage = Math.min(99, Math.round((done / total) * 100))
  return presentation
}
