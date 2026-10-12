import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useDesktopStore, maxSessionWindows } from '@/stores/desktop'
import { useWindowSessionStore } from '@/stores/window-session'
import { useSshStore } from '@/stores/ssh'

const warning = vi.hoisted(() => vi.fn())
vi.mock('@/lib/ui', () => ({ getUiApi: () => ({ message: { warning } }) }))

describe('HostDeck desktop adapter', () => {
  beforeEach(() => {
    localStorage.clear()
    warning.mockClear()
    vi.stubGlobal(
      'matchMedia',
      vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })),
    )
    setActivePinia(createPinia())
    vi.useFakeTimers()
  })
  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
  })

  it('releases window sessions through the host lifecycle after close or reset', async () => {
    const sessions = useWindowSessionStore()
    const disconnect = vi.spyOn(sessions, 'disconnectWindow').mockResolvedValue(undefined)
    const desktop = useDesktopStore()
    const first = desktop.openWindow('terminal')!
    await desktop.requestCloseWindow(first)
    expect(disconnect).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(220)
    expect(disconnect).toHaveBeenCalledWith(first)
    const second = desktop.openWindow('terminal')!
    desktop.closeWindow(second)
    desktop.reset()
    await vi.runAllTimersAsync()
    expect(disconnect.mock.calls).toEqual([[first], [second]])
  })

  it('keeps session-window limits and warnings outside the package', () => {
    const desktop = useDesktopStore()
    for (let index = 0; index < maxSessionWindows; index++) desktop.openWindow('terminal')
    expect(desktop.sessionWindowCount).toBe(maxSessionWindows)
    expect(desktop.openWindow('opencode')).toBeUndefined()
    expect(warning).toHaveBeenCalledOnce()
    expect(desktop.openWindow('files')).toBeTruthy()
    desktop.reset()
  })

  it('injects OpenCode parameters and generic iframe actions from the host', () => {
    useSshStore().host = 'example.org'
    const desktop = useDesktopStore()
    const id = desktop.openWindow('opencode', { startupCommand: 'custom command' })!
    expect(desktop.windows.find((window) => window.id === id)?.props).toMatchObject({
      openIframeUrl: 'http://example.org:4096',
      startupCommand: 'custom command',
    })
    const iframeId = desktop.openWindow('iframe-app', { url: 'https://example.org' })!
    const iframe = desktop.windows.find((window) => window.id === iframeId)!
    desktop.apps['iframe-app']!.actions![0]!.run(iframe)
    expect(iframe.props).toMatchObject({ url: 'https://example.org', refreshToken: Date.now() })
    desktop.reset()
  })

  it('keeps remote shortcuts scoped to their SSH connection', () => {
    const ssh = useSshStore()
    ssh.host = 'first.example'
    ssh.username = 'user'
    ssh.port = 22
    const desktop = useDesktopStore()
    desktop.pinDirectoryToDesktop('/home/user')
    desktop.setPinnedDirectoryPosition('/home/user', 123.6, 78.2)
    expect(desktop.getPinnedDirectoryPositions()).toEqual({ '/home/user': { x: 124, y: 78 } })
    ssh.host = 'second.example'
    expect(desktop.getPinnedDirectories()).toEqual([])
    ssh.host = 'first.example'
    expect(desktop.getPinnedDirectories()).toEqual(['/home/user'])
    desktop.openPinnedDirectory('/home/user')
    expect(desktop.windows[0]).toMatchObject({ appId: 'files', props: { path: '/home/user' } })
    desktop.reset()
  })
})
