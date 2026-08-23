export const editableExtensions = new Set([
  'txt',
  'md',
  'json',
  'yaml',
  'yml',
  'xml',
  'js',
  'ts',
  'tsx',
  'jsx',
  'vue',
  'css',
  'scss',
  'less',
  'html',
  'sh',
  'bash',
  'zsh',
  'py',
  'go',
  'rs',
  'java',
  'c',
  'cpp',
  'h',
  'hpp',
  'sql',
  'ini',
  'conf',
  'env',
  'log',
])

export const imageExtensions = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'ico'])

export const videoExtensions = new Set(['mp4', 'webm', 'ogg', 'mov', 'mkv', 'avi'])

export type FileOpenCategory = 'editable' | 'image' | 'video' | 'unsupported'

export function getFileExtension(filename: string): string {
  return filename.split('.').pop()?.toLowerCase() || ''
}

export function getFileOpenCategory(filename: string): FileOpenCategory {
  const extension = getFileExtension(filename)
  if (editableExtensions.has(extension)) {
    return 'editable'
  }
  if (imageExtensions.has(extension)) {
    return 'image'
  }
  if (videoExtensions.has(extension)) {
    return 'video'
  }
  return 'unsupported'
}

export function isEditableFile(filename: string): boolean {
  return editableExtensions.has(getFileExtension(filename))
}

export function isMediaFile(filename: string): boolean {
  const extension = getFileExtension(filename)
  return imageExtensions.has(extension) || videoExtensions.has(extension)
}
