import { markRaw, toRef } from 'vue'
import { defineStore } from 'pinia'
import { createWidgets } from '@host-deck/webos'
import { desktopWidgetDefinitions } from '@/components/widgets/registry'

export const DESKTOP_WIDGETS_STORAGE_KEY = 'host-deck:desktop:widgets:v1'

export const useDesktopWidgetStore = defineStore('desktopWidget', () => {
  const runtime = createWidgets({
    definitions: Object.values(desktopWidgetDefinitions),
    defaultTypes: ['performance-monitor'],
    storage: window.localStorage,
    storageKey: DESKTOP_WIDGETS_STORAGE_KEY,
  })
  return { ...runtime, runtime: markRaw(runtime), widgets: toRef(runtime, 'widgets') }
})
