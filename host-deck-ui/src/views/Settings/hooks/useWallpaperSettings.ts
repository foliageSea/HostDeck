import { ref } from 'vue'
import { settingsApi } from '@/api/settings'
import type { WallpaperCustomType, WallpaperSettings, WallpaperTarget } from '@/lib/wallpapers'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'

const MAX_WALLPAPER_SIZE = 100 * 1024 * 1024

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

  function applyCustomWallpaper(
    target: WallpaperTarget,
    dataUrl: string,
    customType: WallpaperCustomType,
  ) {
    const nextValue: WallpaperSettings = {
      ...getWallpaperSettings(target),
      mode: 'custom',
      presetId: null,
      customDataUrl: dataUrl,
      customType,
    }

    updateWallpaperSettings(target, nextValue)
  }

  async function handleWallpaperUpload(target: WallpaperTarget, event: Event) {
    const input = event.target as HTMLInputElement
    const file = input.files?.[0]
    input.value = ''

    if (!file) {
      return
    }

    const customType: WallpaperCustomType | null = file.type.startsWith('image/')
      ? 'image'
      : file.type.startsWith('video/')
        ? 'video'
        : null

    if (!customType) {
      getUiApi().message.error('仅支持上传图片或视频文件。')
      return
    }

    if (file.size > MAX_WALLPAPER_SIZE) {
      getUiApi().message.error('文件不能超过 100MB。')
      return
    }

    try {
      const uploadedWallpaper = await settingsApi.uploadWallpaper(target, file)
      applyCustomWallpaper(target, uploadedWallpaper.url, uploadedWallpaper.customType)
      getUiApi().message.success(target === 'desktop' ? '桌面壁纸已更新。' : '登录页壁纸已更新。')
    } catch (error) {
      getUiApi().message.error(error instanceof Error ? error.message : '上传壁纸失败。')
    }
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
