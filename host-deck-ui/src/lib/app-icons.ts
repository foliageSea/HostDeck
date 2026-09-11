import type { AppIconKey } from '@/types/desktop'
import dashboardIconUrl from '@/assets/mac-tahoe/src/apps/scalable/utilities-system-monitor.svg'
import dockerIconUrl from '@/assets/mac-tahoe/src/apps/scalable/docker.svg'
import editorIconUrl from '@/assets/mac-tahoe/src/apps/scalable/accessories-text-editor.svg'
import fallbackAppIconUrl from '@/assets/mac-tahoe/src/apps/scalable/application-default-icon.svg'
import fileManagerIconUrl from '@/assets/mac-tahoe/src/apps/scalable/file-manager.svg'
import linkIconUrl from '@/assets/mac-tahoe/src/apps/scalable/junction.svg'
import logoutIconUrl from '@/assets/mac-tahoe/src/apps/scalable/log-out.svg'
import mediaIconUrl from '@/assets/mac-tahoe/src/apps/scalable/eog.svg'
import operationLogIconUrl from '@/assets/mac-tahoe/src/apps/scalable/gpk-log.svg'
import portForwardIconUrl from '@/assets/mac-tahoe/src/apps/22/network-connect.svg'
import processManagerIconUrl from '@/assets/mac-tahoe/src/apps/scalable/net.nokyan.Resources.svg'
import secureBrowserIconUrl from '@/assets/mac-tahoe/src/apps/scalable/web-browser.svg'
import realtimeLogIconUrl from '@/assets/mac-tahoe/src/apps/scalable/logview.svg'
import runtimeIconUrl from '@/assets/mac-tahoe/src/apps/scalable/multitasking-view.svg'
import settingsIconUrl from '@/assets/mac-tahoe/src/apps/scalable/preferences-system.svg'
import taskIconUrl from '@/assets/mac-tahoe/src/apps/scalable/evolution-tasks.svg'
import taskCenterIconUrl from '@/assets/mac-tahoe/src/apps/scalable/stacks-task-manager.svg'
import terminalIconUrl from '@/assets/mac-tahoe/src/apps/scalable/terminal.svg'

export const themedAppIconMap: Record<AppIconKey, string> = {
  dashboard: dashboardIconUrl,
  'cron-task': taskIconUrl,
  docker: dockerIconUrl,
  editor: editorIconUrl,
  folder: fileManagerIconUrl,
  'iframe-app': fallbackAppIconUrl,
  link: linkIconUrl,
  logout: logoutIconUrl,
  media: mediaIconUrl,
  opencode: '/opencode.ico',
  'operation-log': operationLogIconUrl,
  'realtime-log': realtimeLogIconUrl,
  process: processManagerIconUrl,
  'port-forward': portForwardIconUrl,
  'secure-browser': secureBrowserIconUrl,
  runtime: runtimeIconUrl,
  settings: settingsIconUrl,
  terminal: terminalIconUrl,
  'task-center': taskCenterIconUrl,
}

const preloadedIconUrls = new Map<string, Promise<void>>()

function preloadIconUrl(url: string): Promise<void> {
  const cached = preloadedIconUrls.get(url)
  if (cached) {
    return cached
  }

  const promise = new Promise<void>((resolve) => {
    if (typeof window === 'undefined' || typeof Image === 'undefined') {
      resolve()
      return
    }

    const image = new Image()
    image.decoding = 'async'
    image.onload = () => resolve()
    image.onerror = () => resolve()
    image.src = url

    if (typeof image.decode === 'function') {
      image.decode().then(resolve, resolve)
    }
  })

  preloadedIconUrls.set(url, promise)
  return promise
}

export function preloadAppIcon(name: AppIconKey): Promise<void> {
  return preloadIconUrl(themedAppIconMap[name])
}

export function preloadAppIcons(names: Iterable<AppIconKey>): Promise<void> {
  const urls = new Set<string>()
  for (const name of names) {
    urls.add(themedAppIconMap[name])
  }

  return Promise.all([...urls].map((url) => preloadIconUrl(url))).then(() => undefined)
}

export function clearAppIconCache() {
  preloadedIconUrls.clear()
}
