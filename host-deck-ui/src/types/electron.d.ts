export {}

declare global {
  interface Window {
    hostDeck?: {
      app?: {
        openInBrowser: () => Promise<void>
        openDevTools: () => Promise<void>
        clearBrowserCache: () => Promise<void>
        getExternalAccess: () => Promise<boolean>
        setExternalAccess: (enabled: boolean) => Promise<boolean>
      }
      platform: string
      window?: {
        minimize: () => Promise<void>
        toggleMaximize: () => Promise<boolean>
        close: () => Promise<void>
      }
    }
  }
}
