import {
  getCurrentInstance,
  inject,
  provide,
  shallowRef,
  type Component,
  type ComponentInternalInstance,
  type InjectionKey,
  type ShallowRef,
} from 'vue'
import type { DesktopRuntime } from '../core/desktop'
import { createDesktopPreferences, type DesktopPreferences } from '../core/preferences'
import type { WidgetRuntime } from '../core/widgets'

export interface DesktopContext {
  desktop: DesktopRuntime
  preferences: DesktopPreferences
  widgets?: WidgetRuntime
  resolveIcon?: (name: string) => string | Component | undefined
  preloadIcons?: (names: Iterable<string>) => Promise<void>
  overlayTarget?: ShallowRef<HTMLElement | null>
}

export const desktopContextKey: InjectionKey<DesktopContext> = Symbol('webos-context')
const localContexts = new WeakMap<ComponentInternalInstance, DesktopContext>()

export function provideDesktopContext(context: DesktopContext) {
  const instance = getCurrentInstance()
  if (instance) localContexts.set(instance, context)
  provide(desktopContextKey, context)
  return context
}

export function useDesktopContext() {
  const instance = getCurrentInstance()
  const context = (instance && localContexts.get(instance)) || inject(desktopContextKey)
  if (!context)
    throw new Error('WebOS components require DesktopProvider or provideDesktopContext().')
  return context
}

export function useDesktop() {
  return useDesktopContext().desktop
}
export function useDesktopPreferences() {
  return useDesktopContext().preferences
}

export function createDesktopContext(
  desktop: DesktopRuntime,
  preferences = createDesktopPreferences(),
): DesktopContext {
  return { desktop, preferences, overlayTarget: shallowRef(null) }
}
