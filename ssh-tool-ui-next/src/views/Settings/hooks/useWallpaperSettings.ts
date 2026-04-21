import { ref } from 'vue'
import type { WallpaperSettings, WallpaperTarget } from '@/lib/wallpapers'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'

const MAX_WALLPAPER_SIZE = 10 * 1024 * 1024

export function useWallpaperSettings() {
  const settingsStore = useSettingsStore()
  const desktopWallpaperInput = ref<HTMLInputElement | null>(null)
  const loginWallpaperInput = ref<HTMLInputElement | null>(null)

  function getWallpaperSettings(target: WallpaperTarget): WallpaperSettings {
    return target === 'desktop' ? settingsStore.desktopWallpaper : settingsStore.loginWallpaper
  }

  function updateWallpaperSettings(target: WallpaperTarget, nextValue: WallpaperSettings) {
    if (target === 'desktop') {
      settingsStore.setDesktopWallpaper(nextValue)
      return
    }

    settingsStore.setLoginWallpaper(nextValue)
  }

  function setPresetWallpaper(target: WallpaperTarget, presetId: string) {
    const nextValue: WallpaperSettings = {
      ...getWallpaperSettings(target),
      mode: 'preset',
      presetId,
      customDataUrl: null,
    }

    updateWallpaperSettings(target, nextValue)
  }

  function resetWallpaper(target: WallpaperTarget) {
    if (target === 'desktop') {
      settingsStore.resetDesktopWallpaper()
      return
    }

    settingsStore.resetLoginWallpaper()
  }

  function openWallpaperPicker(target: WallpaperTarget) {
    const input = target === 'desktop' ? desktopWallpaperInput.value : loginWallpaperInput.value
    input?.click()
  }

  function applyCustomWallpaper(target: WallpaperTarget, dataUrl: string) {
    const nextValue: WallpaperSettings = {
      ...getWallpaperSettings(target),
      mode: 'custom',
      presetId: null,
      customDataUrl: dataUrl,
    }

    updateWallpaperSettings(target, nextValue)
  }

  function handleWallpaperUpload(target: WallpaperTarget, event: Event) {
    const input = event.target as HTMLInputElement
    const file = input.files?.[0]
    input.value = ''

    if (!file) {
      return
    }

    if (!file.type.startsWith('image/')) {
      getUiApi().message.error('仅支持上传图片文件。')
      return
    }

    if (file.size > MAX_WALLPAPER_SIZE) {
      getUiApi().message.error('图片不能超过 10MB。')
      return
    }

    const reader = new FileReader()
    reader.onload = () => {
      const result = typeof reader.result === 'string' ? reader.result : ''
      if (!result) {
        getUiApi().message.error('读取图片失败。')
        return
      }

      applyCustomWallpaper(target, result)
      getUiApi().message.success(target === 'desktop' ? '桌面壁纸已更新。' : '登录页壁纸已更新。')
    }
    reader.onerror = () => {
      getUiApi().message.error('读取图片失败。')
    }
    reader.readAsDataURL(file)
  }

  function isPresetActive(target: WallpaperTarget, presetId: string) {
    const settings = getWallpaperSettings(target)
    return settings.mode === 'preset' && settings.presetId === presetId
  }

  function isDefaultActive(target: WallpaperTarget) {
    return getWallpaperSettings(target).mode === 'default'
  }

  function isCustomActive(target: WallpaperTarget) {
    return getWallpaperSettings(target).mode === 'custom'
  }

  return {
    desktopWallpaperInput,
    handleWallpaperUpload,
    isCustomActive,
    isDefaultActive,
    isPresetActive,
    loginWallpaperInput,
    openWallpaperPicker,
    resetWallpaper,
    settingsStore,
    setPresetWallpaper,
  }
}
