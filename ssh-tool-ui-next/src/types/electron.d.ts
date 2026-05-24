export {}

declare global {
  interface Window {
    sshTool?: {
      app?: {
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
