const DOCK_ITEM_SIZE = 52
const DOCK_GAP = 12
const DOCK_PADDING = 10
const VERTICAL_TRACK_PADDING = 20
const MIN_DOCK_SCALE = 0.01

export function calculateDockScale(options: {
  availableSize: number
  itemCount: number
  separatorCount: number
  vertical: boolean
}) {
  const { availableSize, itemCount, separatorCount, vertical } = options
  if (availableSize <= 0 || itemCount <= 0) return 1

  const gapCount = Math.max(0, itemCount + separatorCount - 1)
  const scalableSize =
    itemCount * DOCK_ITEM_SIZE +
    gapCount * DOCK_GAP +
    DOCK_PADDING * 2 +
    (vertical ? VERTICAL_TRACK_PADDING * 2 : 0)
  const fixedSize = separatorCount

  const scale = Math.max(
    MIN_DOCK_SCALE,
    Math.min(1, Math.max(0, availableSize - fixedSize) / scalableSize),
  )
  return Math.floor(scale * 1000) / 1000
}
