export const archiveExtensions = [
  '.tar.gz',
  '.tar.bz2',
  '.tar.xz',
  '.tgz',
  '.tbz2',
  '.txz',
  '.tar',
  '.zip',
] as const

export type ArchiveExtension = (typeof archiveExtensions)[number]

export function getArchiveExtension(filename: string): ArchiveExtension | null {
  const lowerName = filename.toLowerCase()
  return archiveExtensions.find((extension) => lowerName.endsWith(extension)) ?? null
}

export function getExtractDirectoryName(filename: string): string {
  const extension = getArchiveExtension(filename)
  if (!extension) {
    return filename
  }

  const baseName = filename.slice(0, filename.length - extension.length)
  return baseName || filename
}
