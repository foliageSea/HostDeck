export interface DockerViewProps {
  windowId?: string
  connectionId?: string
  host?: string
  username?: string
}

export type DockerTabName =
  | 'overview'
  | 'containers'
  | 'images'
  | 'networks'
  | 'volumes'
  | 'compose'

export interface DangerActionConfirmOptions {
  title: string
  content: string
  positiveText: string
  action: () => Promise<void> | void
}
