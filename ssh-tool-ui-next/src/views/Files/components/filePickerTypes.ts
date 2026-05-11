import type { FileItem } from '@/api/files'

export type FilePickerMode = 'file' | 'directory' | 'both'

export interface FilePickerSelection {
  currentPath: string
  item: FileItem | null
  path: string
}

export interface FilePickerConfirmPayload {
  currentPath: string
  selections: FilePickerSelection[]
}
