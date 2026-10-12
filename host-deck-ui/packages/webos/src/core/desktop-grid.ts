export const DESKTOP_GRID_CELL_WIDTH = 96
export const DESKTOP_GRID_CELL_HEIGHT = 108
export const DESKTOP_GRID_GAP_X = 28
export const DESKTOP_GRID_GAP_Y = 28
export const DESKTOP_GRID_PADDING = 20

export const DESKTOP_GRID_STEP_X = DESKTOP_GRID_CELL_WIDTH + DESKTOP_GRID_GAP_X
export const DESKTOP_GRID_STEP_Y = DESKTOP_GRID_CELL_HEIGHT + DESKTOP_GRID_GAP_Y

export interface DesktopGridPosition {
  x: number
  y: number
}

export interface DesktopGridCell {
  column: number
  row: number
}

export interface DesktopGridSpan {
  columns: number
  rows: number
}

export type DesktopGridCellKey = string

export function getDesktopGridRowCount(contentHeight: number) {
  const availableHeight = Math.max(
    DESKTOP_GRID_CELL_HEIGHT,
    contentHeight - DESKTOP_GRID_PADDING * 2,
  )

  return Math.max(1, Math.floor(availableHeight / DESKTOP_GRID_STEP_Y))
}

export function getDesktopGridPosition(cell: DesktopGridCell): DesktopGridPosition {
  return {
    x: DESKTOP_GRID_PADDING + cell.column * DESKTOP_GRID_STEP_X,
    y: DESKTOP_GRID_PADDING + cell.row * DESKTOP_GRID_STEP_Y,
  }
}

export function getDesktopGridCellKey(cell: DesktopGridCell): DesktopGridCellKey {
  return `${cell.column}:${cell.row}`
}

export function getDesktopGridCellFromKey(key: DesktopGridCellKey): DesktopGridCell {
  const [column, row] = key.split(':').map(Number)
  return {
    column: Number.isFinite(column) ? column : 0,
    row: Number.isFinite(row) ? row : 0,
  }
}

export function getDesktopGridCellAtPosition(x: number, y: number, contentHeight: number) {
  const rowCount = getDesktopGridRowCount(contentHeight)
  return {
    column: Math.max(0, Math.round((x - DESKTOP_GRID_PADDING) / DESKTOP_GRID_STEP_X)),
    row: Math.min(
      rowCount - 1,
      Math.max(0, Math.round((y - DESKTOP_GRID_PADDING) / DESKTOP_GRID_STEP_Y)),
    ),
  }
}

export function getDesktopGridPositionByIndex(index: number, contentHeight: number) {
  const rowCount = getDesktopGridRowCount(contentHeight)
  const column = Math.max(0, Math.floor(index / rowCount))
  const row = Math.max(0, index % rowCount)
  return getDesktopGridPosition({ column, row })
}

export function getDesktopGridIndex(cell: DesktopGridCell, contentHeight: number) {
  return cell.column * getDesktopGridRowCount(contentHeight) + cell.row
}

export function getDesktopGridSpan(width: number, height: number): DesktopGridSpan {
  return {
    columns: Math.max(1, Math.ceil((width + DESKTOP_GRID_GAP_X) / DESKTOP_GRID_STEP_X)),
    rows: Math.max(1, Math.ceil((height + DESKTOP_GRID_GAP_Y) / DESKTOP_GRID_STEP_Y)),
  }
}

export function getDesktopGridCells(
  position: DesktopGridPosition,
  width: number,
  height: number,
  contentHeight: number,
) {
  const anchor = getDesktopGridCellAtPosition(position.x, position.y, contentHeight)
  const span = getDesktopGridSpan(width, height)
  const cells: DesktopGridCellKey[] = []

  for (let column = anchor.column; column < anchor.column + span.columns; column += 1) {
    for (let row = anchor.row; row < anchor.row + span.rows; row += 1) {
      cells.push(getDesktopGridCellKey({ column, row }))
    }
  }

  return cells
}

function isGridAreaAvailable(
  cell: DesktopGridCell,
  span: DesktopGridSpan,
  occupiedCells: Set<DesktopGridCellKey>,
) {
  for (let column = cell.column; column < cell.column + span.columns; column += 1) {
    for (let row = cell.row; row < cell.row + span.rows; row += 1) {
      if (occupiedCells.has(getDesktopGridCellKey({ column, row }))) {
        return false
      }
    }
  }

  return true
}

export function resolveDesktopGridCell(
  preferredCell: DesktopGridCell,
  span: DesktopGridSpan,
  occupiedCells: Set<DesktopGridCellKey>,
  contentHeight: number,
  searchSpan: number,
) {
  const preferredIndex = Math.max(0, getDesktopGridIndex(preferredCell, contentHeight))
  const maxDistance = Math.max(
    searchSpan,
    (occupiedCells.size + 1) * Math.max(span.columns, span.rows),
  )

  for (let distance = 0; distance <= maxDistance; distance += 1) {
    const candidateIndexes =
      distance === 0 ? [preferredIndex] : [preferredIndex + distance, preferredIndex - distance]

    for (const candidateIndex of candidateIndexes) {
      if (candidateIndex < 0) {
        continue
      }

      const rowCount = getDesktopGridRowCount(contentHeight)
      const candidate: DesktopGridCell = {
        column: Math.floor(candidateIndex / rowCount),
        row: candidateIndex % rowCount,
      }

      if (isGridAreaAvailable(candidate, span, occupiedCells)) {
        return candidate
      }
    }
  }

  return {
    column: preferredCell.column,
    row: preferredCell.row,
  }
}

export function occupyDesktopGridCells(
  occupiedCells: Set<DesktopGridCellKey>,
  cell: DesktopGridCell,
  span: DesktopGridSpan,
) {
  for (let column = cell.column; column < cell.column + span.columns; column += 1) {
    for (let row = cell.row; row < cell.row + span.rows; row += 1) {
      occupiedCells.add(getDesktopGridCellKey({ column, row }))
    }
  }
}

export function clampDesktopGridPosition(
  x: number,
  y: number,
  width: number,
  height: number,
  contentWidth: number,
  contentHeight: number,
) {
  const maxX = Math.max(DESKTOP_GRID_PADDING, contentWidth - width - DESKTOP_GRID_PADDING)
  const maxY = Math.max(DESKTOP_GRID_PADDING, contentHeight - height - DESKTOP_GRID_PADDING)

  return {
    x: Math.min(Math.max(x, DESKTOP_GRID_PADDING), maxX),
    y: Math.min(Math.max(y, DESKTOP_GRID_PADDING), maxY),
  }
}

export function snapDesktopGridPosition(
  x: number,
  y: number,
  width: number,
  height: number,
  contentWidth: number,
  contentHeight: number,
) {
  const cell = getDesktopGridCellAtPosition(x, y, contentHeight)
  const position = getDesktopGridPosition(cell)
  return clampDesktopGridPosition(
    position.x,
    position.y,
    width,
    height,
    contentWidth,
    contentHeight,
  )
}
