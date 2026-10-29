import { getUiApi } from '@/lib/ui'

interface AxiosLikeError {
  code?: unknown
  message?: unknown
  response?: {
    status?: unknown
  }
}

const PERMISSION_DENIED_MESSAGE = '权限不足，无法访问该目录。'
const NOT_FOUND_MESSAGE = '目录不存在或已被删除。'
const FALLBACK_MESSAGE = '无法访问该目录，请稍后重试。'

type FileOpenErrorKind = 'permissionDenied' | 'notFound' | 'unauthorized' | 'unknown'

const NOTIFICATION_DEDUPE_WINDOW = 1500
const notifiedAt = new Map<string, number>()

function readString(value: unknown) {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : ''
}

function readStatus(error: AxiosLikeError) {
  const status = error.response?.status
  return typeof status === 'number' ? status : Number.NaN
}

/**
 * Buckets a file-manager open failure into a small set of kinds. Classification is
 * driven by the kind (not by the rendered text) so the dedupe key stays stable even
 * when the backend wording changes between calls.
 */
function classifyFileOpenError(error: unknown): FileOpenErrorKind {
  const axiosLike = (error ?? {}) as AxiosLikeError
  const rawMessage = readString(axiosLike.message)
  const rawCode = readString(String(axiosLike.code ?? ''))
  const status = readStatus(axiosLike)
  const combined = `${rawMessage} ${rawCode}`.toLowerCase()

  if (
    combined.includes('permission denied') ||
    combined.includes('permission_denied') ||
    combined.includes('eacces') ||
    combined.includes('权限不足') ||
    combined.includes('statuserror: code 3') ||
    /(^|\s)code 3(\s|$)/.test(combined) ||
    status === 403
  ) {
    return 'permissionDenied'
  }

  if (
    combined.includes('no such file') ||
    combined.includes('not exist') ||
    combined.includes('not found') ||
    combined.includes('enoent') ||
    combined.includes('不存在') ||
    combined.includes('statuserror: code 2') ||
    /(^|\s)code 2(\s|$)/.test(combined) ||
    status === 404
  ) {
    return 'notFound'
  }

  if (status === 401) {
    return 'unauthorized'
  }

  return 'unknown'
}

/**
 * Builds a short human readable description for a failed directory open, embedding
 * the target path and the reason reported by the backend.
 */
export function describeFileOpenError(path: string, error: unknown): string {
  const targetPath = path || '该目录'
  const kind = classifyFileOpenError(error)

  if (kind === 'permissionDenied') {
    return `无法打开目录 ${targetPath}：${PERMISSION_DENIED_MESSAGE}`
  }

  if (kind === 'notFound') {
    return `无法打开目录 ${targetPath}：${NOT_FOUND_MESSAGE}`
  }

  if (kind === 'unauthorized') {
    return `无法打开目录 ${targetPath}：登录状态已失效，请重新连接后再试。`
  }

  const rawMessage = readString((error as AxiosLikeError | null)?.message)
  if (!rawMessage) {
    return `无法打开目录 ${targetPath}：${FALLBACK_MESSAGE}`
  }

  return `无法打开目录 ${targetPath}：${rawMessage}`
}

/**
 * Returns true when the same notification has not been shown within the dedupe window.
 * Concurrent calls (same key) also collapse because the timestamp is recorded immediately.
 */
export function shouldNotifyOnce(
  key: string,
  options?: { now?: number; windowMs?: number },
): boolean {
  const now = options?.now ?? Date.now()
  const windowMs = options?.windowMs ?? NOTIFICATION_DEDUPE_WINDOW
  const lastNotifiedAt = notifiedAt.get(key)

  if (lastNotifiedAt !== undefined && now - lastNotifiedAt < windowMs) {
    return false
  }

  notifiedAt.set(key, now)
  return true
}

/** Clears the dedupe cache; mainly useful in tests. */
export function resetNotifyOnceCache() {
  notifiedAt.clear()
}

/** Shows a deduplicated error bubble for a directory open failure. */
export function notifyFileOpenError(path: string, error: unknown) {
  // Key on path + error kind (not the rendered text) so a wording change on the
  // backend side cannot bypass the dedupe window for the same directory.
  const key = `file-open-error:${path || '该目录'}:${classifyFileOpenError(error)}`
  if (!shouldNotifyOnce(key)) {
    return
  }

  getUiApi().message.error(describeFileOpenError(path, error))
}
