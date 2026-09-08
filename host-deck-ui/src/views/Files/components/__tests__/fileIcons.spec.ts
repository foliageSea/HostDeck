import { describe, expect, it } from 'vitest'
import blankIconUrl from '@/assets/mac-tahoe/src/mimes/scalable/application-blank.svg'
import databaseIconUrl from '@/assets/mac-tahoe/src/mimes/scalable/application-sql.svg'
import folderIconUrl from '@/assets/mac-tahoe/src/places/scalable/folder.svg'
import markdownIconUrl from '@/assets/mac-tahoe/src/mimes/scalable/text-markdown.svg'
import pdfIconUrl from '@/assets/mac-tahoe/src/mimes/scalable/application-pdf.svg'
import pythonIconUrl from '@/assets/mac-tahoe/src/mimes/scalable/text-x-python.svg'
import typescriptIconUrl from '@/assets/mac-tahoe/src/mimes/scalable/text-x-typescript.svg'
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
