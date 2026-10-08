import { defineStore } from 'pinia'
import { desktopWidgetDefinitions, desktopWidgetTypes } from '@/components/widgets/registry'
import type { DesktopWidgetInstance, DesktopWidgetType } from '@/types/desktop-widget'

export const DESKTOP_WIDGETS_STORAGE_KEY = 'host-deck:desktop:widgets:v1'

function createWidget(type: DesktopWidgetType): DesktopWidgetInstance {
  return {
    id: desktopWidgetDefinitions[type].singleInstance
      ? type
      : `${type}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    type,
    x: null,
    y: 24,
  }
}

function createDefaultWidgets() {
  return [createWidget('performance-monitor')]
}

function normalizeCoordinate(value: unknown) {
  return typeof value === 'number' && Number.isFinite(value) ? Math.round(value) : null
}

function normalizeWidgets(value: unknown): DesktopWidgetInstance[] {
  if (!Array.isArray(value)) return createDefaultWidgets()

  const ids = new Set<string>()
  const singletonTypes = new Set<DesktopWidgetType>()
  const widgets: DesktopWidgetInstance[] = []

  for (const item of value) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) continue
    const candidate = item as Partial<DesktopWidgetInstance>
    if (!desktopWidgetTypes.includes(candidate.type as DesktopWidgetType)) continue

    const type = candidate.type as DesktopWidgetType
    const definition = desktopWidgetDefinitions[type]
    const id = typeof candidate.id === 'string' && candidate.id.trim() ? candidate.id : type
    if (ids.has(id) || (definition.singleInstance && singletonTypes.has(type))) continue

    ids.add(id)
    if (definition.singleInstance) singletonTypes.add(type)
    widgets.push({
      id,
      type,
      x: normalizeCoordinate(candidate.x),
      y: normalizeCoordinate(candidate.y) ?? 24,
    })
  }

  return widgets
}

function loadWidgets() {
  if (typeof window === 'undefined') return createDefaultWidgets()
  const storedValue = window.localStorage.getItem(DESKTOP_WIDGETS_STORAGE_KEY)
  if (storedValue === null) return createDefaultWidgets()

  try {
    return normalizeWidgets(JSON.parse(storedValue))
  } catch {
    return createDefaultWidgets()
  }
}

function persistWidgets(widgets: DesktopWidgetInstance[]) {
  if (typeof window !== 'undefined') {
    window.localStorage.setItem(DESKTOP_WIDGETS_STORAGE_KEY, JSON.stringify(widgets))
  }
}

export const useDesktopWidgetStore = defineStore('desktopWidget', {
  state: () => ({
    widgets: loadWidgets(),
  }),
  actions: {
    addWidget(type: DesktopWidgetType) {
      const definition = desktopWidgetDefinitions[type]
      if (!definition) return null

      if (definition.singleInstance) {
        const existingWidget = this.widgets.find((widget) => widget.type === type)
        if (existingWidget) return existingWidget.id
      }

      const widget = createWidget(type)
      this.widgets.push(widget)
      persistWidgets(this.widgets)
      return widget.id
    },

    hasWidget(type: DesktopWidgetType) {
      return this.widgets.some((widget) => widget.type === type)
    },

    removeWidget(id: string) {
      const nextWidgets = this.widgets.filter((widget) => widget.id !== id)
      if (nextWidgets.length === this.widgets.length) return false

      this.widgets = nextWidgets
      persistWidgets(this.widgets)
      return true
    },

    updateWidgetPosition(id: string, x: number, y: number) {
      const widget = this.widgets.find((item) => item.id === id)
      if (!widget || !Number.isFinite(x) || !Number.isFinite(y)) return false

      widget.x = Math.round(x)
      widget.y = Math.round(y)
      persistWidgets(this.widgets)
      return true
    },
  },
})
