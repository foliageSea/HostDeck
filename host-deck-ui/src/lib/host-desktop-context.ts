import { inject, shallowRef, type Component, type ComponentOptions } from 'vue'
import { desktopContextKey, provideDesktopContext } from '@host-deck/webos'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useDesktopWidgetStore } from '@/stores/desktop-widget'
import { themedAppIconMap, preloadAppIcons } from '@/lib/app-icons'
import type { AppIconKey } from '@/types/desktop'

/** Preserve existing component entry points while supplying the package's context. */
export function withHostDesktop<T extends Component>(component: T): T {
  const options = component as ComponentOptions
  return {
    ...options,
    setup(props, context) {
      const existing = inject(desktopContextKey, null)
      if (!existing) {
        provideDesktopContext({
          desktop: useDesktopStore().runtime,
          preferences: useSettingsStore(),
          widgets: useDesktopWidgetStore().runtime,
          resolveIcon: (name) => themedAppIconMap[name as AppIconKey],
          preloadIcons: (names) => preloadAppIcons(Array.from(names) as AppIconKey[]),
          overlayTarget: shallowRef(null),
        })
      }
      return options.setup?.(props, context)
    },
  } as T
}
