export type BrowserNotificationPermission = NotificationPermission | 'unsupported'

export type BrowserNotificationSupport = 'supported' | 'insecure-context' | 'unsupported'

export interface BrowserNotificationOptions {
  title: string
  body?: string
  tag?: string
  icon?: string
  onClick?: () => void
}

function notificationApi(): typeof Notification | null {
  if (typeof window === 'undefined' || typeof Notification === 'undefined') return null
  return Notification
}

/** Whether the current page can use the Web Notifications API at all. */
export function browserNotificationSupport(): BrowserNotificationSupport {
  if (!notificationApi()) return 'unsupported'
  if (typeof window.isSecureContext === 'boolean' && !window.isSecureContext) {
    return 'insecure-context'
  }
  return 'supported'
}

export function browserNotificationPermission(): BrowserNotificationPermission {
  if (browserNotificationSupport() !== 'supported') return 'unsupported'
  return notificationApi()!.permission
}

/** Requests permission when the browser has not decided yet; otherwise returns the current state. */
export async function requestBrowserNotificationPermission(): Promise<BrowserNotificationPermission> {
  const api = notificationApi()
  if (!api || browserNotificationSupport() !== 'supported') return 'unsupported'
  if (api.permission !== 'default') return api.permission
  try {
    return await api.requestPermission()
  } catch {
    return api.permission
  }
}

/** Shows a system notification when permission was granted; returns null when it was skipped. */
export function showBrowserNotification(options: BrowserNotificationOptions): Notification | null {
  const api = notificationApi()
  if (!api || browserNotificationSupport() !== 'supported') return null
  if (api.permission !== 'granted') return null
  try {
    const notification = new api(options.title, {
      body: options.body,
      tag: options.tag,
      icon: options.icon,
    })
    notification.onclick = () => {
      try {
        window.focus()
      } catch {
        // Focusing can fail when the page is already closed; the click still counts.
      }
      options.onClick?.()
      try {
        notification.close()
      } catch {
        // Closing is best effort.
      }
    }
    return notification
  } catch {
    return null
  }
}
