export {}

declare global {
  interface Window {
    sshTool?: {
      app?: {
        openInBrowser: () => Promise<void>
        clearBrowserCache: () => Promise<void>
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
