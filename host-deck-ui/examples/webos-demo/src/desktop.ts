import { createDesktop, createDesktopContext, createWidgets } from '@host-deck/webos'
import Welcome from './apps/Welcome.vue'
import Counter from './apps/Counter.vue'
import Editor from './apps/Editor.vue'
import ClockWidget from './apps/ClockWidget.vue'

function icon(text: string, color: string) {
  return `data:image/svg+xml,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" rx="16" fill="${color}"/><text x="32" y="42" text-anchor="middle" font-family="sans-serif" font-size="32" fill="white">${text}</text></svg>`)}`
}

export function createDemoDesktop(storage: Storage | null = window.localStorage) {
  const desktop = createDesktop({
    storage,
    storageKey: 'webos-demo:dock:v1',
    defaultDockAppIds: ['welcome', 'counter', 'editor'],
    apps: [
      {
        id: 'welcome',
        title: '欢迎',
        icon: icon('W', '#0891b2'),
        component: Welcome,
        width: 620,
        height: 380,
        showInLaunchpad: true,
      },
      {
        id: 'counter',
        title: '计数器',
        icon: icon('+', '#7c3aed'),
        component: Counter,
        width: 420,
        height: 320,
        singleInstance: false,
        showInLaunchpad: true,
      },
      {
        id: 'editor',
        title: '编辑器',
        icon: icon('E', '#d97706'),
        component: Editor,
        width: 620,
        height: 440,
        showInLaunchpad: true,
      },
    ],
  })
  const context = createDesktopContext(desktop)
  context.widgets = createWidgets({
    storage,
    storageKey: 'webos-demo:widgets:v1',
    defaultTypes: ['clock'],
    definitions: [
      {
        type: 'clock',
        title: '自定义时钟',
        component: ClockWidget,
        width: 280,
        height: 130,
        singleInstance: true,
      },
    ],
  })
  return context
}
