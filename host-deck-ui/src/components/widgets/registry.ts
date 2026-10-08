import PerformanceMonitorWidget from './PerformanceMonitorWidget.vue'
import type { DesktopWidgetDefinition, DesktopWidgetType } from '@/types/desktop-widget'

export const desktopWidgetDefinitions: Record<DesktopWidgetType, DesktopWidgetDefinition> = {
  'performance-monitor': {
    component: PerformanceMonitorWidget,
    detailsAppId: 'dashboard',
    detailsProps: { initialTab: 'performance' },
    height: 306,
    singleInstance: true,
    title: '性能监控',
    type: 'performance-monitor',
    width: 390,
  },
}

export const desktopWidgetTypes = Object.keys(desktopWidgetDefinitions) as DesktopWidgetType[]
