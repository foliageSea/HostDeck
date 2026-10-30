import { h } from 'vue'
import { registerSW } from 'virtual:pwa-register'
import RoundedButton from '@/components/common/RoundedButton.vue'
import { getUiApi } from '@/lib/ui'
import type { NotificationReactive } from 'naive-ui'

const UPDATE_INTERVAL = 60 * 60 * 1000

export function initializePwa() {
  if (
    !import.meta.env.PROD ||
    window.hostDeck ||
    !window.isSecureContext ||
    !('serviceWorker' in navigator)
  ) {
    return () => {}
  }

  let registration: ServiceWorkerRegistration | undefined
  let updateTimer: ReturnType<typeof setInterval> | undefined
  let notification: NotificationReactive | undefined
  let disposed = false

  function checkForUpdate() {
    if (navigator.onLine && document.visibilityState === 'visible') {
      void registration?.update().catch((error: unknown) => {
        console.warn('Unable to check for HostDeck updates.', error)
      })
    }
  }

  const updateServiceWorker = registerSW({
    onNeedRefresh() {
      if (disposed || notification) return

      notification = getUiApi().notification.info({
        title: 'HostDeck 有新版本',
        content: '刷新后生效，请先保存编辑内容并完成正在进行的任务。',
        duration: 0,
        action: () =>
          h(
            RoundedButton,
            {
              size: 'small',
              type: 'primary',
              onClick: () => {
                getUiApi().dialog.warning({
                  title: '更新 HostDeck',
                  content: '刷新会中断当前终端连接和传输任务，确定刷新？',
                  positiveText: '刷新更新',
                  negativeText: '稍后',
                  onPositiveClick: () => updateServiceWorker(true),
                })
              },
            },
            { default: () => '刷新更新' },
          ),
        onAfterLeave() {
          notification = undefined
        },
      })
    },
    onRegisteredSW(_url, swRegistration) {
      if (disposed || !swRegistration) return
      registration = swRegistration
      updateTimer = setInterval(checkForUpdate, UPDATE_INTERVAL)
      document.addEventListener('visibilitychange', checkForUpdate)
      window.addEventListener('online', checkForUpdate)
    },
    onRegisterError(error: unknown) {
      console.warn('Unable to register the HostDeck service worker.', error)
    },
  })

  return () => {
    disposed = true
    clearInterval(updateTimer)
    document.removeEventListener('visibilitychange', checkForUpdate)
    window.removeEventListener('online', checkForUpdate)
    notification?.destroy()
  }
}
