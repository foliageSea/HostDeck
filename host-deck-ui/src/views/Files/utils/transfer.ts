export function getUploadRelativePath(file: File): string {
  return 'webkitRelativePath' in file && typeof file.webkitRelativePath === 'string'
    ? file.webkitRelativePath
    : file.name
}

export function getUploadDirectory(relativePath: string): string {
  const segments = relativePath.split('/').filter(Boolean)
  segments.pop()
  return segments.join('/')
}

export function getUploadFilename(relativePath: string, file: File): string {
  const segments = relativePath.split('/').filter(Boolean)
  return segments.at(-1) ?? file.name
}

export function isTransferCancelled(error: unknown): boolean {
  return (
    typeof error === 'object' && error !== null && 'code' in error && error.code === 'ERR_CANCELED'
  )
}

export function getDownloadProgress(loaded: number, total: number): number {
  if (total <= 0) {
    return loaded > 0 ? 1 : 0
  }

  return Math.min(100, Math.round((Math.min(loaded, total) / total) * 100))
}
