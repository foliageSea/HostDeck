export {}

declare global {
  interface Window {
    sshTool?: {
      platform: string
      window?: {
        minimize: () => Promise<void>
        toggleMaximize: () => Promise<boolean>
        close: () => Promise<void>
      }
    }
  }
}
