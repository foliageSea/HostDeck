import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  browserNotificationPermission,
  browserNotificationSupport,
  requestBrowserNotificationPermission,
  showBrowserNotification,
} from '@/lib/browser-notification'

class FakeNotification {
  static permission: NotificationPermission = 'granted'
  static requestPermission = vi.fn(async () => FakeNotification.permission)
  static instances: FakeNotification[] = []

  title: string
  options?: NotificationOptions
  onclick: ((event: Event) => void) | null = null
  close = vi.fn()

  constructor(title: string, options?: NotificationOptions) {
    this.title = title
    this.options = options
    FakeNotification.instances.push(this)
  }
}

function installNotificationApi(permission: NotificationPermission = 'granted') {
  FakeNotification.permission = permission
  FakeNotification.instances = []
  FakeNotification.requestPermission = vi.fn(async () => FakeNotification.permission)
  vi.stubGlobal('Notification', FakeNotification)
}

function setSecureContext(value: boolean | undefined) {
  Object.defineProperty(window, 'isSecureContext', { configurable: true, value })
}

describe('browser notification helper', () => {
  beforeEach(() => {
    setSecureContext(undefined)
    Object.defineProperty(window, 'focus', { configurable: true, value: vi.fn(), writable: true })
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it('reports the environment as unsupported when the Notification API is missing', async () => {
    expect(browserNotificationSupport()).toBe('unsupported')
    expect(browserNotificationPermission()).toBe('unsupported')
    await expect(requestBrowserNotificationPermission()).resolves.toBe('unsupported')
    expect(showBrowserNotification({ title: 'done' })).toBeNull()
  })

  it('reports insecure contexts instead of pretending notifications work', () => {
    installNotificationApi()
    setSecureContext(false)
    expect(browserNotificationSupport()).toBe('insecure-context')
    expect(browserNotificationPermission()).toBe('unsupported')
    expect(showBrowserNotification({ title: 'done' })).toBeNull()
  })

  it('maps the browser permission state', () => {
    installNotificationApi('default')
    expect(browserNotificationSupport()).toBe('supported')
    expect(browserNotificationPermission()).toBe('default')
    FakeNotification.permission = 'denied'
    expect(browserNotificationPermission()).toBe('denied')
    FakeNotification.permission = 'granted'
    expect(browserNotificationPermission()).toBe('granted')
  })

  it('requests permission only while the browser has not decided', async () => {
    installNotificationApi('default')
    FakeNotification.requestPermission.mockResolvedValue('granted')
    await expect(requestBrowserNotificationPermission()).resolves.toBe('granted')
    expect(FakeNotification.requestPermission).toHaveBeenCalledTimes(1)

    FakeNotification.permission = 'granted'
    await expect(requestBrowserNotificationPermission()).resolves.toBe('granted')
    expect(FakeNotification.requestPermission).toHaveBeenCalledTimes(1)
  })

  it('keeps the current permission when the request throws', async () => {
    installNotificationApi('default')
    FakeNotification.requestPermission.mockRejectedValue(new Error('blocked'))
    await expect(requestBrowserNotificationPermission()).resolves.toBe('default')
  })

  it('shows a notification and focuses the window when it is clicked', () => {
    installNotificationApi('granted')
    const onClick = vi.fn()
    const notification = showBrowserNotification({
      body: 'Maintain host · done',
      onClick,
      tag: 'ai-agent-run-1',
      title: 'AI Agent 任务已完成',
    })

    expect(notification).toBeInstanceOf(FakeNotification)
    expect(FakeNotification.instances).toHaveLength(1)
    expect(FakeNotification.instances[0]!.title).toBe('AI Agent 任务已完成')
    expect(FakeNotification.instances[0]!.options).toMatchObject({
      body: 'Maintain host · done',
      tag: 'ai-agent-run-1',
    })

    notification!.onclick?.(new Event('click'))
    expect(window.focus).toHaveBeenCalledTimes(1)
    expect(onClick).toHaveBeenCalledTimes(1)
    expect(FakeNotification.instances[0]!.close).toHaveBeenCalledTimes(1)
  })

  it('does not show notifications without permission', () => {
    installNotificationApi('denied')
    expect(showBrowserNotification({ title: 'AI Agent 任务已完成' })).toBeNull()
    expect(FakeNotification.instances).toHaveLength(0)
  })

  it('swallows constructor failures', () => {
    installNotificationApi('granted')
    class ThrowingNotification {
      static permission: NotificationPermission = 'granted'

      constructor() {
        throw new Error('not available')
      }
    }
    vi.stubGlobal('Notification', ThrowingNotification)
    expect(showBrowserNotification({ title: 'AI Agent 任务已完成' })).toBeNull()
  })
})
