export {}

declare global {
  interface Window {
    hostDeck?: {
      app?: {
        openInBrowser: () => Promise<void>
        openDevTools: () => Promise<void>
        forceReload: () => Promise<void>
        clearBrowserCache: () => Promise<void>
        getExternalAccess: () => Promise<boolean>
        setExternalAccess: (enabled: boolean) => Promise<boolean>
      }
      platform: string
      shellMode?: 'native-tabs'
      window?: {
        minimize: () => Promise<void>
        toggleMaximize: () => Promise<boolean>
        close: () => Promise<void>
      }
    }
    hostDeckTabs?: {
      activate: (id: string) => Promise<TabState>
      close: (id: string) => Promise<TabState>
      create: () => Promise<string>
      list: () => Promise<TabState>
      onChanged: (callback: (state: TabState) => void) => () => void
      openActiveDevTools: () => Promise<void>
      openActiveInBrowser: () => Promise<void>
      platform: string
      rename: (id: string, title: string) => Promise<TabState>
      reloadActive: () => Promise<void>
      setBarPosition: (position: TabBarPosition) => Promise<TabState>
      window: {
        minimize: () => Promise<void>
        toggleMaximize: () => Promise<boolean>
        close: () => Promise<void>
      }
    }
  }

  interface TabState {
    activeTabId: string | null
    tabBarPosition: TabBarPosition
    tabs: Array<{
      id: string
      customTitle: string | null
      isActive: boolean
      isLoading: boolean
      title: string
      url: string
    }>
  }

  type TabBarPosition = 'top' | 'left'

  const __APP_VERSION__: string
}
