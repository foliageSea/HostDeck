import { beforeEach, describe, expect, it, vi } from 'vitest'
import { filesApi, type FileItem } from '@/api/files'
import { createFileStore } from '@/stores/file'

vi.mock('@/api/files', () => ({
  filesApi: { list: vi.fn() },
}))

const directory = (filename: string): FileItem => ({
  filename,
  isDirectory: true,
  longname: filename,
  size: 0,
})

const file = (filename: string): FileItem => ({
  filename,
  isDirectory: false,
  longname: filename,
  size: 1,
})

function createStore() {
  return createFileStore({
    connectionId: 'conn-1',
    host: 'example.com',
    port: 22,
    username: 'root',
  })
}

function createPermissionError() {
  return new Error('SftpStatusError: Permission denied(code 3)')
}

describe('file store directory loading', () => {
  beforeEach(() => {
    window.localStorage.clear()
    vi.mocked(filesApi.list).mockReset()
  })

  it('loads a directory and commits the path on success', async () => {
    vi.mocked(filesApi.list).mockResolvedValueOnce([directory('var'), file('notes.txt')])
    const store = createStore()

    await store.fetchFiles('/var')

    expect(filesApi.list).toHaveBeenCalledWith('conn-1', '/var')
    expect(store.currentPath).toBe('/var')
    expect(store.files.map((item) => item.filename)).toEqual(['var', 'notes.txt'])
    expect(store.loading).toBe(false)
  })

  it('keeps currentPath and files when the listing fails', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('var')])
      .mockRejectedValueOnce(createPermissionError())
    const store = createStore()

    await store.fetchFiles('/')
    await expect(store.fetchFiles('/root')).rejects.toThrow('Permission denied')

    expect(store.currentPath).toBe('/')
    expect(store.files.map((item) => item.filename)).toEqual(['var'])
    expect(store.loading).toBe(false)
  })

  it('resets loading and rethrows when the first listing fails', async () => {
    vi.mocked(filesApi.list).mockRejectedValueOnce(createPermissionError())
    const store = createStore()

    await expect(store.fetchFiles('/')).rejects.toThrow('Permission denied')

    expect(store.loading).toBe(false)
    expect(store.currentPath).toBe('/')
    expect(store.files).toEqual([])
  })

  it('surfaces failures through navigateTo without touching history', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('var')])
      .mockRejectedValueOnce(createPermissionError())
    const store = createStore()

    await store.fetchFiles('/')
    await expect(store.navigateTo('/root')).rejects.toThrow('Permission denied')

    expect(store.currentPath).toBe('/')
    expect(store.backHistory).toEqual([])
    expect(store.forwardHistory).toEqual([])
    expect(store.loading).toBe(false)
  })

  it('does not push history when navigating forward fails', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('var')])
      .mockResolvedValueOnce([directory('log')])
      .mockResolvedValueOnce([directory('var')])
      .mockRejectedValueOnce(createPermissionError())
    const store = createStore()

    await store.fetchFiles('/')
    await store.navigateTo('/var')
    await store.navigateBack()

    expect(store.currentPath).toBe('/')
    expect(store.forwardHistory).toEqual(['/var'])

    await expect(store.navigateForward()).rejects.toThrow('Permission denied')

    expect(store.currentPath).toBe('/')
    expect(store.forwardHistory).toEqual(['/var'])
    expect(store.backHistory).toEqual([])
    expect(store.loading).toBe(false)
  })

  it('does not pop back history when going back fails', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('var')])
      .mockResolvedValueOnce([directory('log')])
      .mockRejectedValueOnce(createPermissionError())
    const store = createStore()

    await store.fetchFiles('/')
    await store.navigateTo('/var')
    await expect(store.navigateBack()).rejects.toThrow('Permission denied')

    expect(store.currentPath).toBe('/var')
    expect(store.backHistory).toEqual(['/'])
    expect(store.forwardHistory).toEqual([])
    expect(store.loading).toBe(false)
  })

  it('shows the failing path to the caller when going up fails', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('child')])
      .mockRejectedValueOnce(createPermissionError())
    const store = createStore()

    await store.fetchFiles('/root/child')
    await expect(store.navigateUp()).rejects.toThrow('Permission denied')

    expect(store.currentPath).toBe('/root/child')
    expect(store.files.map((item) => item.filename)).toEqual(['child'])
    expect(store.loading).toBe(false)
  })
})
