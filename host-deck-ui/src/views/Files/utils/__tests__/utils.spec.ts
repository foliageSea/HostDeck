import { describe, expect, it, vi } from 'vitest'
import {
  archiveExtensions,
  createPermissionMatrix,
  editableExtensions,
  formatFavoritePath,
  formatFileSize,
  formatModifyTime,
  getArchiveExtension,
  getDownloadProgress,
  getExtractDirectoryName,
  getFileOpenCategory,
  getPermissionFromLongname,
  getUploadDirectory,
  getUploadFilename,
  getUploadRelativePath,
  imageExtensions,
  isEditableFile,
  isMediaFile,
  isTransferCancelled,
  permissionMatrixToMode,
  permissionModeToMatrix,
  permissionToMode,
  videoExtensions,
} from '..'

describe('file format utilities', () => {
  it.each([
    [0, '0 B'],
    [1023, '1023 B'],
    [1024, '1.0 KB'],
    [1536, '1.5 KB'],
    [1024 * 1024, '1.00 MB'],
    [1024 * 1024 * 1024, '1.00 GB'],
  ])('formats %i bytes as %s', (size, expected) => {
    expect(formatFileSize(size)).toBe(expected)
  })

  it('formats valid times and preserves empty or invalid values', () => {
    const localeSpy = vi.spyOn(Date.prototype, 'toLocaleString').mockReturnValue('localized time')

    expect(formatModifyTime('2026-08-23T10:00:00Z')).toBe('localized time')
    expect(localeSpy).toHaveBeenCalledWith('zh-CN')
    expect(formatModifyTime()).toBe('-')
    expect(formatModifyTime('not-a-date')).toBe('not-a-date')

    localeSpy.mockRestore()
  })

  it('formats favorite paths using their basename', () => {
    expect(formatFavoritePath('/var/log/')).toBe('log')
    expect(formatFavoritePath('/')).toBe('根目录')
  })
})

describe('archive utilities', () => {
  it('keeps compound archive extensions ahead of shorter matches', () => {
    expect(archiveExtensions.indexOf('.tar.gz')).toBeLessThan(archiveExtensions.indexOf('.tar'))
    expect(getArchiveExtension('BACKUP.TAR.GZ')).toBe('.tar.gz')
    expect(getArchiveExtension('backup.tar')).toBe('.tar')
    expect(getArchiveExtension('backup.txt')).toBeNull()
  })

  it('removes the full archive extension from extraction directory names', () => {
    expect(getExtractDirectoryName('backup.tar.bz2')).toBe('backup')
    expect(getExtractDirectoryName('BACKUP.ZIP')).toBe('BACKUP')
    expect(getExtractDirectoryName('notes.txt')).toBe('notes.txt')
    expect(getExtractDirectoryName('.zip')).toBe('.zip')
  })
})

describe('permission utilities', () => {
  it('creates independent empty permission matrices', () => {
    const first = createPermissionMatrix()
    const second = createPermissionMatrix()

    first.owner.read = true
    expect(second.owner.read).toBe(false)
  })

  it('extracts and validates permissions from longname values', () => {
    expect(getPermissionFromLongname('-rw-r--r-- 1 user group 12 file.txt')).toBe('-rw-r--r--')
    expect(getPermissionFromLongname('drwxr-xr-x')).toBe('drwxr-xr-x')
    expect(getPermissionFromLongname('invalid file')).toBe('-')
    expect(getPermissionFromLongname()).toBe('-')
  })

  it.each([
    ['-rw-r--r--', '644'],
    ['drwxr-xr-x', '755'],
    ['-rwsr-Sr-t', '745'],
  ])('converts %s to mode %s', (permission, mode) => {
    expect(permissionToMode(permission)).toBe(mode)
  })

  it('rejects invalid permission strings', () => {
    expect(permissionToMode('rwxr-xr-x')).toBeNull()
  })

  it('converts three- and four-digit modes to matrices', () => {
    expect(permissionModeToMatrix('0754')).toEqual(permissionModeToMatrix('754'))
    expect(permissionModeToMatrix('754')).toEqual({
      owner: { read: true, write: true, execute: true },
      group: { read: true, write: false, execute: true },
      others: { read: true, write: false, execute: false },
    })
  })

  it('converts permission matrices back to modes', () => {
    expect(permissionMatrixToMode(permissionModeToMatrix('640'))).toBe('640')
    expect(permissionMatrixToMode(createPermissionMatrix())).toBe('000')
  })
})

describe('file opening utilities', () => {
  it('exports the existing extension categories', () => {
    expect(editableExtensions.has('vue')).toBe(true)
    expect(imageExtensions.has('webp')).toBe(true)
    expect(videoExtensions.has('mkv')).toBe(true)
  })

  it('classifies filenames case-insensitively', () => {
    expect(getFileOpenCategory('README.MD')).toBe('editable')
    expect(getFileOpenCategory('photo.PNG')).toBe('image')
    expect(getFileOpenCategory('movie.MP4')).toBe('video')
    expect(getFileOpenCategory('archive.zip')).toBe('unsupported')
    expect(isEditableFile('config.JSON')).toBe(true)
    expect(isMediaFile('clip.webm')).toBe(true)
  })
})

describe('transfer utilities', () => {
  it('uses webkitRelativePath when a directory upload provides it', () => {
    const file = new File(['data'], 'app.log')
    Object.defineProperty(file, 'webkitRelativePath', { value: 'logs/2026/app.log' })

    expect(getUploadRelativePath(file)).toBe('logs/2026/app.log')
    expect(getUploadDirectory(getUploadRelativePath(file))).toBe('logs/2026')
    expect(getUploadFilename(getUploadRelativePath(file), file)).toBe('app.log')
  })

  it('falls back to the file name for ordinary uploads', () => {
    const file = new File(['data'], 'app.log')

    expect(getUploadRelativePath(file)).toBe('app.log')
    expect(getUploadDirectory('app.log')).toBe('')
    expect(getUploadFilename('', file)).toBe('app.log')
  })

  it('preserves an empty browser-provided relative path', () => {
    const file = new File(['data'], 'app.log')
    Object.defineProperty(file, 'webkitRelativePath', { value: '' })

    expect(getUploadRelativePath(file)).toBe('')
  })

  it('normalizes empty path segments consistently', () => {
    const file = new File(['data'], 'fallback.txt')

    expect(getUploadDirectory('/folder//nested/file.txt/')).toBe('folder/nested')
    expect(getUploadFilename('/folder//nested/file.txt/', file)).toBe('file.txt')
  })

  it('detects cancelled transfers by error code', () => {
    expect(isTransferCancelled({ code: 'ERR_CANCELED' })).toBe(true)
    expect(isTransferCancelled({ code: 'OTHER' })).toBe(false)
    expect(isTransferCancelled(null)).toBe(false)
  })

  it.each([
    [0, 0, 0],
    [1, 0, 1],
    [25, 100, 25],
    [99.5, 100, 100],
    [120, 100, 100],
  ])('calculates progress for %s of %s as %s', (loaded, total, expected) => {
    expect(getDownloadProgress(loaded, total)).toBe(expected)
  })
})
