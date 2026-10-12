import { describe, expect, it } from 'vitest'
import { createWidgets } from '../widgets'

const definitions = [
  {
    type: 'clock',
    title: 'Clock',
    component: { render: () => null },
    width: 280,
    height: 140,
    singleInstance: true,
  },
  { type: 'custom', title: 'Custom', component: { render: () => null }, width: 280, height: 140 },
]

describe('widget registry', () => {
  it('supports registering additional widget types at runtime', () => {
    const widgets = createWidgets()
    widgets.registerWidget(definitions[0]!)
    expect(widgets.addWidget('clock')).toBe('clock')
    expect(() => widgets.registerWidget(definitions[0]!)).toThrow('Invalid')
  })
  it('accepts host widgets, persists layouts and preserves empty layouts', () => {
    const data = new Map<string, string>()
    const storage = {
      getItem: (key: string) => data.get(key) ?? null,
      setItem: (key: string, value: string) => {
        data.set(key, value)
      },
    }
    const options = { definitions, storage, defaultTypes: ['clock'] }
    const widgets = createWidgets(options)
    expect(widgets.addWidget('clock')).toBe('clock')
    expect(widgets.widgets).toHaveLength(1)
    expect(widgets.addWidget('custom')).not.toBe(widgets.addWidget('custom'))
    expect(widgets.addWidget('unknown')).toBeNull()
    expect(widgets.updateWidgetPosition('clock', 123.8, 12.2)).toBe(true)
    expect(createWidgets(options).widgets[0]).toMatchObject({ x: 124, y: 12 })
    widgets.widgets.forEach((widget) => widgets.removeWidget(widget.id))
    expect(createWidgets(options).widgets).toEqual([])
  })

  it('filters unknown types, duplicates and invalid coordinates', () => {
    const widgets = createWidgets({
      definitions,
      storage: {
        getItem: () =>
          JSON.stringify([
            { id: 'clock', type: 'clock', x: 'invalid', y: null },
            { id: 'second', type: 'clock' },
            { id: 'unknown', type: 'unknown' },
          ]),
        setItem: () => {},
      },
    })
    expect(widgets.widgets).toEqual([{ id: 'clock', type: 'clock', x: null, y: 24 }])
    expect(widgets.updateWidgetPosition('clock', Infinity, 0)).toBe(false)
  })
})
