<script setup lang="ts">
import WallpaperSection from './components/WallpaperSection.vue'
import { useWallpaperSettings } from './hooks/useWallpaperSettings'

const controller = useWallpaperSettings()
const { settingsStore } = controller
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
        <WallpaperSection
          target="desktop"
          title="桌面壁纸"
          description="支持预设背景或上传本地图片，上传图片会保存在当前浏览器。"
          default-label="跟随当前主题"
          preset-label="桌面预设"
          :controller="controller"
        />

        <WallpaperSection
          target="login"
          title="登录页壁纸"
          description="登录页可独立设置，方便区分欢迎页和桌面工作区。"
          default-label="登录页原始风格"
          preset-label="登录页预设"
          :controller="controller"
        />
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
  overflow-y: auto;
  scrollbar-width: none;
  -ms-overflow-style: none;
}

.settings-view::-webkit-scrollbar {
  width: 0;
  height: 0;
  display: none;
}

.wallpaper-section + .wallpaper-section {
  padding-top: 4px;
}

@media (max-width: 768px) {
  .settings-view {
    padding: 16px;
  }
}
</style>
