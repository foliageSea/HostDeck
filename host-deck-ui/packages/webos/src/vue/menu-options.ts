export interface DesktopMenuOption {
  key: string
  label: string
  disabled?: boolean
  danger?: boolean
  children?: DesktopMenuOption[]
}
