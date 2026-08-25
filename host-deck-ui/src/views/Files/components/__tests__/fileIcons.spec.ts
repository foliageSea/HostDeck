import { describe, expect, it } from 'vitest'
import blankIconUrl from '@/assets/file-icons/mac-tahoe/application-blank.svg'
import databaseIconUrl from '@/assets/file-icons/mac-tahoe/application-sql.svg'
import folderIconUrl from '@/assets/file-icons/mac-tahoe/folder.svg'
import markdownIconUrl from '@/assets/file-icons/mac-tahoe/text-markdown.svg'
import pdfIconUrl from '@/assets/file-icons/mac-tahoe/application-pdf.svg'
import pythonIconUrl from '@/assets/file-icons/mac-tahoe/text-x-python.svg'
import typescriptIconUrl from '@/assets/file-icons/mac-tahoe/text-x-typescript.svg'
import { getFileIcon, getFilePreviewType } from '../fileIcons'

function target(filename: string, isDirectory = false) {
  return { filename, isDirectory }
}

describe('fileIcons', () => {
  it.each([
    [target('src', true), folderIconUrl],
    [target('README'), markdownIconUrl],
    [target('REPORT.PDF'), pdfIconUrl],
    [target('server.ts'), typescriptIconUrl],
    [target('main.py'), pythonIconUrl],
    [target('records.sqlite3'), databaseIconUrl],
    [target('unrecognized.extension'), blankIconUrl],
  ])('maps $filename to its MacTahoe icon', (file, expectedSrc) => {
    expect(getFileIcon(file).src).toBe(expectedSrc)
  })

  it('keeps media preview behavior separate from visual icon selection', () => {
    expect(getFilePreviewType(target('photo.JPG'))).toBe('image')
    expect(getFilePreviewType(target('clip.mp4'))).toBe('video')
    expect(getFilePreviewType(target('document.pdf'))).toBeNull()
    expect(getFilePreviewType(target('photos', true))).toBeNull()
  })
})
