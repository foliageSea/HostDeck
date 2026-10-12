import { markRaw, reactive } from 'vue'
import type { StorageAdapter, WidgetDefinition, WidgetInstance } from './types'

export interface WidgetOptions {
  definitions?: WidgetDefinition[]
  defaultTypes?: string[]
  storage?: StorageAdapter | null
  storageKey?: string
}

export function createWidgets(options: WidgetOptions = {}) {
  const definitions: Record<string, WidgetDefinition> = Object.create(null)
  options.definitions?.forEach((definition) => {
    if (
      !definition.type ||
      Object.hasOwn(definitions, definition.type) ||
      ['__proto__', 'constructor', 'prototype'].includes(definition.type)
    ) {
      throw new Error(`Invalid widget type: ${definition.type}`)
    }
    definitions[definition.type] = { ...definition, component: markRaw(definition.component) }
  })
  const state = reactive({ definitions, widgets: [] as WidgetInstance[] })
  let sequence = 0
  const storageKey = options.storageKey ?? 'webos:widgets:v1'
  const storage = options.storage
  function createWidget(type: string): WidgetInstance {
    return {
      id: definitions[type]?.singleInstance ? type : `${type}-${Date.now()}-${sequence++}`,
      type,
      x: null,
      y: 24,
    }
  }
  function persist() {
    try {
      storage?.setItem(storageKey, JSON.stringify(state.widgets))
    } catch {
      /* Storage is optional. */
    }
  }
  try {
    const stored = storage?.getItem(storageKey)
    const value: unknown = stored == null ? null : JSON.parse(stored)
    if (Array.isArray(value)) {
      const ids = new Set<string>()
      const singletonTypes = new Set<string>()
      for (const item of value) {
        if (!item || typeof item !== 'object') continue
        const widget = item as Partial<WidgetInstance>
        const definition = typeof widget.type === 'string' ? definitions[widget.type] : undefined
        if (!definition || !widget.type) continue
        const id = typeof widget.id === 'string' && widget.id.trim() ? widget.id : widget.type
        if (ids.has(id) || (definition.singleInstance && singletonTypes.has(widget.type))) continue
        ids.add(id)
        singletonTypes.add(widget.type)
        state.widgets.push({
          id,
          type: widget.type,
          x:
            typeof widget.x === 'number' && Number.isFinite(widget.x) ? Math.round(widget.x) : null,
          y: typeof widget.y === 'number' && Number.isFinite(widget.y) ? Math.round(widget.y) : 24,
        })
      }
    } else {
      state.widgets = (options.defaultTypes ?? [])
        .filter((type) => definitions[type])
        .map(createWidget)
    }
  } catch {
    state.widgets = (options.defaultTypes ?? [])
      .filter((type) => definitions[type])
      .map(createWidget)
  }
  return Object.assign(state, {
    registerWidget(definition: WidgetDefinition) {
      if (
        !definition.type ||
        Object.hasOwn(state.definitions, definition.type) ||
        ['__proto__', 'constructor', 'prototype'].includes(definition.type)
      ) {
        throw new Error(`Invalid widget type: ${definition.type}`)
      }
      state.definitions[definition.type] = {
        ...definition,
        component: markRaw(definition.component),
      }
    },
    addWidget(type: string) {
      const definition = definitions[type]
      if (!definition) return null
      const existing = state.widgets.find((widget) => widget.type === type)
      if (definition.singleInstance && existing) return existing.id
      const widget = createWidget(type)
      state.widgets.push(widget)
      persist()
      return widget.id
    },
    hasWidget(type: string) {
      return state.widgets.some((widget) => widget.type === type)
    },
    removeWidget(id: string) {
      const next = state.widgets.filter((widget) => widget.id !== id)
      if (next.length === state.widgets.length) return false
      state.widgets = next
      persist()
      return true
    },
    updateWidgetPosition(id: string, x: number, y: number) {
      const widget = state.widgets.find((item) => item.id === id)
      if (!widget || !Number.isFinite(x) || !Number.isFinite(y)) return false
      widget.x = Math.round(x)
      widget.y = Math.round(y)
      persist()
      return true
    },
  })
}

export type WidgetRuntime = ReturnType<typeof createWidgets>
