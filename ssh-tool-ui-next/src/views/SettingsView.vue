<script setup lang="ts">
import { ref } from 'vue'
import {
  wallpaperPresets,
  type WallpaperSettings,
  type WallpaperTarget,
} from '@/lib/wallpapers'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'

const settingsStore = useSettingsStore()
const desktopWallpaperInput = ref<HTMLInputElement | null>(null)
const loginWallpaperInput = ref<HTMLInputElement | null>(null)
const MAX_WALLPAPER_SIZE = 10 * 1024 * 1024

function getWallpaperSettings(target: WallpaperTarget): WallpaperSettings {
  return target === 'desktop' ? settingsStore.desktopWallpaper : settingsStore.loginWallpaper
}

function setPresetWallpaper(target: WallpaperTarget, presetId: string) {
  const nextValue: WallpaperSettings = {
    mode: 'preset',
    presetId,
    customDataUrl: null,
  }

  if (target === 'desktop') {
    settingsStore.setDesktopWallpaper(nextValue)
    return
  }

  settingsStore.setLoginWallpaper(nextValue)
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
    mode: 'custom',
    presetId: null,
    customDataUrl: dataUrl,
  }

  if (target === 'desktop') {
    settingsStore.setDesktopWallpaper(nextValue)
    return
  }

  settingsStore.setLoginWallpaper(nextValue)
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
</script>

<template>
  <div class="settings-view">
    <NCard title="基础设置" size="large">
      <NForm label-placement="top">
        <NFormItem label="主题模式">
          <NRadioGroup :value="settingsStore.themeMode" @update:value="settingsStore.setTheme">
            <NSpace>
              <NRadio value="system">跟随系统</NRadio>
              <NRadio value="dark">深色</NRadio>
              <NRadio value="light">浅色</NRadio>
            </NSpace>
          </NRadioGroup>
        </NFormItem>
      </NForm>
    </NCard>

    <NCard title="壁纸设置" size="large">
      <NSpace vertical :size="24">
        <section class="wallpaper-section">
          <div class="wallpaper-header">
            <div>
              <h3>桌面壁纸</h3>
              <p>支持预设背景或上传本地图片，上传图片会保存在当前浏览器。</p>
            </div>
            <NSpace>
              <NButton secondary @click="openWallpaperPicker('desktop')">上传图片</NButton>
              <NButton tertiary @click="resetWallpaper('desktop')">恢复默认</NButton>
            </NSpace>
          </div>

          <input
            ref="desktopWallpaperInput"
            class="wallpaper-file-input"
            type="file"
            accept="image/*"
            @change="handleWallpaperUpload('desktop', $event)"
          >

          <div class="wallpaper-grid">
            <button
              type="button"
              class="wallpaper-option"
              :class="{ 'wallpaper-option-active': isDefaultActive('desktop') }"
              @click="resetWallpaper('desktop')"
            >
              <div class="wallpaper-preview wallpaper-preview-default desktop-default-preview" />
              <div class="wallpaper-option-meta">
                <strong>默认</strong>
                <span>跟随当前主题</span>
              </div>
            </button>

            <button
              v-for="preset in wallpaperPresets"
              :key="`desktop-${preset.id}`"
              type="button"
              class="wallpaper-option"
              :class="{ 'wallpaper-option-active': isPresetActive('desktop', preset.id) }"
              @click="setPresetWallpaper('desktop', preset.id)"
            >
              <div class="wallpaper-preview" :style="{ background: preset.background }" />
              <div class="wallpaper-option-meta">
                <strong>{{ preset.label }}</strong>
                <span>桌面预设</span>
              </div>
            </button>

            <div class="wallpaper-option wallpaper-option-static" :class="{ 'wallpaper-option-active': isCustomActive('desktop') }">
              <div
                class="wallpaper-preview"
                :style="settingsStore.desktopWallpaper.customDataUrl
                  ? { backgroundImage: `url(${settingsStore.desktopWallpaper.customDataUrl})`, backgroundSize: 'cover', backgroundPosition: 'center' }
                  : undefined"
              >
                <span v-if="!settingsStore.desktopWallpaper.customDataUrl" class="wallpaper-empty">未上传</span>
              </div>
              <div class="wallpaper-option-meta">
                <strong>自定义图片</strong>
                <span>最大 10MB</span>
              </div>
            </div>
          </div>
        </section>

        <section class="wallpaper-section">
          <div class="wallpaper-header">
            <div>
              <h3>登录页壁纸</h3>
              <p>登录页可独立设置，方便区分欢迎页和桌面工作区。</p>
            </div>
            <NSpace>
              <NButton secondary @click="openWallpaperPicker('login')">上传图片</NButton>
              <NButton tertiary @click="resetWallpaper('login')">恢复默认</NButton>
            </NSpace>
          </div>

          <input
            ref="loginWallpaperInput"
            class="wallpaper-file-input"
            type="file"
            accept="image/*"
            @change="handleWallpaperUpload('login', $event)"
          >

          <div class="wallpaper-grid">
            <button
              type="button"
              class="wallpaper-option"
              :class="{ 'wallpaper-option-active': isDefaultActive('login') }"
              @click="resetWallpaper('login')"
            >
              <div class="wallpaper-preview wallpaper-preview-default login-default-preview" />
              <div class="wallpaper-option-meta">
                <strong>默认</strong>
                <span>登录页原始风格</span>
              </div>
            </button>

            <button
              v-for="preset in wallpaperPresets"
              :key="`login-${preset.id}`"
              type="button"
              class="wallpaper-option"
              :class="{ 'wallpaper-option-active': isPresetActive('login', preset.id) }"
              @click="setPresetWallpaper('login', preset.id)"
            >
              <div class="wallpaper-preview" :style="{ background: preset.background }" />
              <div class="wallpaper-option-meta">
                <strong>{{ preset.label }}</strong>
                <span>登录页预设</span>
              </div>
            </button>

            <div class="wallpaper-option wallpaper-option-static" :class="{ 'wallpaper-option-active': isCustomActive('login') }">
              <div
                class="wallpaper-preview"
                :style="settingsStore.loginWallpaper.customDataUrl
                  ? { backgroundImage: `url(${settingsStore.loginWallpaper.customDataUrl})`, backgroundSize: 'cover', backgroundPosition: 'center' }
                  : undefined"
              >
                <span v-if="!settingsStore.loginWallpaper.customDataUrl" class="wallpaper-empty">未上传</span>
              </div>
              <div class="wallpaper-option-meta">
                <strong>自定义图片</strong>
                <span>最大 10MB</span>
              </div>
            </div>
          </div>
        </section>
      </NSpace>
    </NCard>
  </div>
</template>

<style scoped>
.settings-view {
  height: 100%;
  padding: 20px;
  display: grid;
  gap: 20px;
}

.wallpaper-section + .wallpaper-section {
  padding-top: 4px;
}

.wallpaper-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 16px;
}

.wallpaper-header h3 {
  margin: 0;
  font-size: 1rem;
}

.wallpaper-header p {
  margin: 6px 0 0;
  color: rgba(100, 116, 139, 0.92);
  font-size: 0.9rem;
}

.wallpaper-file-input {
  display: none;
}

.wallpaper-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 14px;
}

.wallpaper-option {
  padding: 10px;
  border: 1px solid rgba(148, 163, 184, 0.22);
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.72);
  color: inherit;
  text-align: left;
  cursor: pointer;
  transition: border-color 0.18s ease, transform 0.18s ease, box-shadow 0.18s ease;
}

.wallpaper-option:hover {
  transform: translateY(-1px);
}

.wallpaper-option-active {
  border-color: rgba(59, 130, 246, 0.56);
  box-shadow: 0 0 0 1px rgba(96, 165, 250, 0.22);
}

.wallpaper-option-static {
  cursor: default;
}

.wallpaper-preview {
  position: relative;
  height: 92px;
  border-radius: 12px;
  background-color: rgba(148, 163, 184, 0.14);
  background-repeat: no-repeat;
  background-position: center;
  background-size: cover;
  overflow: hidden;
}

.wallpaper-preview-default.desktop-default-preview {
  background:
    radial-gradient(circle at 15% 18%, rgba(59, 130, 246, 0.16), transparent 24%),
    radial-gradient(circle at 85% 15%, rgba(217, 70, 239, 0.14), transparent 18%),
    linear-gradient(160deg, #dbeafe 0%, #e2e8f0 50%, #cbd5e1 100%);
}

.wallpaper-preview-default.login-default-preview {
  background:
    radial-gradient(circle at 20% 20%, rgba(56, 189, 248, 0.2), transparent 24%),
    radial-gradient(circle at 80% 16%, rgba(168, 85, 247, 0.18), transparent 22%),
    linear-gradient(135deg, rgba(15, 23, 42, 0.78), rgba(2, 6, 23, 0.92));
}

.wallpaper-option-meta {
  display: grid;
  gap: 4px;
  margin-top: 10px;
}

.wallpaper-option-meta strong {
  font-size: 0.94rem;
}

.wallpaper-option-meta span {
  color: rgba(100, 116, 139, 0.92);
  font-size: 0.84rem;
}

.wallpaper-empty {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: rgba(71, 85, 105, 0.9);
  font-size: 0.84rem;
  background: rgba(255, 255, 255, 0.46);
}

@media (max-width: 768px) {
  .settings-view {
    padding: 16px;
  }

  .wallpaper-header {
    flex-direction: column;
  }
}
</style>
