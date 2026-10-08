import type { Component } from 'vue'
import type { DesktopAppId } from '@/types/desktop'

export type DesktopWidgetType = 'performance-monitor'

export interface DesktopWidgetInstance {
  id: string
  type: DesktopWidgetType
  x: number | null
  y: number | null
}

export interface DesktopWidgetDefinition {
  type: DesktopWidgetType
  title: string
  component: Component
  width: number
  height: number
  singleInstance?: boolean
  detailsAppId?: DesktopAppId
  detailsProps?: Record<string, unknown>
}
