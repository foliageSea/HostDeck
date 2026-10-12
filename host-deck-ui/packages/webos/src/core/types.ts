import type { Component } from 'vue'

export interface AppConfig {
  id: string
  title: string
  icon: string
  component: Component
  width?: number
  height?: number
  minWidth?: number
  minHeight?: number
  maximizable?: boolean
  minimizable?: boolean
  resizable?: boolean
  singleInstance?: boolean
  hide?: boolean
  showInLaunchpad?: boolean
  defaultProps?: Record<string, unknown> | (() => Record<string, unknown>)
  actions?: WindowAction[]
}

export interface WindowAction {
  id: string
  label: string
  run: (window: WindowState) => void | Promise<void>
}

export type WindowBeforeCloseHandler = () => boolean | Promise<boolean>

export interface OpenWindowOptions {
  maximizable?: boolean
  minimizable?: boolean
  parentId?: string
  resizable?: boolean
}

export interface WindowState {
  id: string
  appId: string
  title: string
  icon: string
  x: number
  y: number
  width: number
  height: number
  minWidth: number
  minHeight: number
  maximizable: boolean
  minimizable: boolean
  resizable: boolean
  parentId?: string
  isMinimized: boolean
  isMaximized: boolean
  zIndex: number
  isClosing: boolean
  isClosePending: boolean
  beforeClose?: WindowBeforeCloseHandler
  props?: Record<string, unknown>
}

export interface StorageAdapter {
  getItem: (key: string) => string | null
  setItem: (key: string, value: string) => void
}

export interface DesktopOptions {
  apps?: AppConfig[]
  defaultDockAppIds?: string[]
  storage?: StorageAdapter | null
  storageKey?: string
  closeAnimationMs?: number
  getBounds?: () => { width: number; height: number }
  shouldMaximize?: (app: AppConfig) => boolean
  canOpen?: (app: AppConfig, windows: WindowState[]) => boolean
  onOpenRejected?: (app: AppConfig) => void
  onWindowClosed?: (window: WindowState) => void | Promise<void>
  onLifecycleError?: (error: unknown) => void
}

export interface DesktopShortcut {
  id: string
  title: string
  icon: string
  x?: number | null
  y?: number | null
  open: () => void
}

export interface WidgetDefinition {
  type: string
  title: string
  component: Component
  width: number
  height: number
  singleInstance?: boolean
  detailsAppId?: string
  detailsProps?: Record<string, unknown>
}

export interface WidgetInstance {
  id: string
  type: string
  x: number | null
  y: number | null
}
