import { describe, expect, it } from 'vitest'
import {
  DESKTOP_GRID_CELL_HEIGHT,
  DESKTOP_GRID_CELL_WIDTH,
  DESKTOP_GRID_GAP_X,
  DESKTOP_GRID_GAP_Y,
  DESKTOP_GRID_PADDING,
  getDesktopGridCellAtPosition,
  getDesktopGridCells,
  getDesktopGridPositionByIndex,
  getDesktopGridSpan,
  occupyDesktopGridCells,
  resolveDesktopGridCell,
} from '@/lib/desktop-grid'

const contentHeight = 700

describe('desktop grid', () => {
  it('uses the same column-first positions as desktop shortcuts', () => {
    expect(getDesktopGridPositionByIndex(0, contentHeight)).toEqual({
      x: DESKTOP_GRID_PADDING,
      y: DESKTOP_GRID_PADDING,
    })
    expect(getDesktopGridPositionByIndex(1, contentHeight)).toEqual({
      x: DESKTOP_GRID_PADDING,
      y: DESKTOP_GRID_PADDING + DESKTOP_GRID_CELL_HEIGHT + DESKTOP_GRID_GAP_Y,
    })
  })

  it('calculates a widget footprint across multiple grid cells', () => {
    expect(getDesktopGridSpan(390, 306)).toEqual({ columns: 4, rows: 3 })

    expect(
      getDesktopGridCells(
        { x: DESKTOP_GRID_PADDING, y: DESKTOP_GRID_PADDING },
        390,
        306,
        contentHeight,
      ),
    ).toHaveLength(12)
  })

  it('moves a widget to the next free area when its preferred area is occupied', () => {
    const occupiedCells = new Set(
      getDesktopGridCells(
        { x: DESKTOP_GRID_PADDING, y: DESKTOP_GRID_PADDING },
        390,
        306,
        contentHeight,
      ),
    )
    const cell = resolveDesktopGridCell(
      getDesktopGridCellAtPosition(DESKTOP_GRID_PADDING, DESKTOP_GRID_PADDING, contentHeight),
      { columns: 4, rows: 3 },
      occupiedCells,
      contentHeight,
      20,
    )

    expect(cell).toEqual({ column: 0, row: 3 })
  })

  it('reserves all cells covered by a widget', () => {
    const occupiedCells = new Set<string>()
    occupyDesktopGridCells(occupiedCells, { column: 2, row: 1 }, { columns: 2, rows: 2 })

    expect(occupiedCells).toEqual(new Set(['2:1', '2:2', '3:1', '3:2']))
  })

  it('uses the shared horizontal step', () => {
    expect(getDesktopGridPositionByIndex(4, contentHeight).x).toBe(
      DESKTOP_GRID_PADDING + DESKTOP_GRID_CELL_WIDTH + DESKTOP_GRID_GAP_X,
    )
  })
})
