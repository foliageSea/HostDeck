import { describe, expect, it } from 'vitest'
import { calculateDockScale } from '../dock-layout'

describe('Dock layout', () => {
  it('keeps the standard size when every item fits', () => {
    expect(
      calculateDockScale({
        availableSize: 1200,
        itemCount: 10,
        separatorCount: 1,
        vertical: true,
      }),
    ).toBe(1)
  })

  it('shrinks a vertical Dock to fit all items in the available height', () => {
    const scale = calculateDockScale({
      availableSize: 820,
      itemCount: 16,
      separatorCount: 1,
      vertical: true,
    })

    expect(scale).toBeLessThan(1)
    expect(scale).toBeCloseTo(819 / 1084, 2)
  })

  it('keeps shrinking an extremely crowded Dock so it still fits', () => {
    const scale = calculateDockScale({
      availableSize: 300,
      itemCount: 40,
      separatorCount: 2,
      vertical: true,
    })

    expect(scale).toBeLessThan(0.25)
    expect(scale).toBeCloseTo(298 / 2632, 2)
  })
})
