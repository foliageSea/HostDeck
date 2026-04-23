<script setup lang="ts">
import WallpaperSection from './components/WallpaperSection.vue'
import { useWallpaperSettings } from './hooks/useWallpaperSettings'

const controller = useWallpaperSettings()
const { settingsStore } = controller
</script>

<template>
  <div class="settings-view scrollbar-none grid h-full gap-[20px] overflow-y-auto p-[20px] lt-md:p-[16px]">
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
          default-label="跟随当前主题"
          preset-label="桌面预设"
          :controller="controller"
        />
      </NSpace>
    </NCard>
  </div>
</template>

<style scoped>
.settings-view::-webkit-scrollbar {
  width: 0;
  height: 0;
  display: none;
}

.wallpaper-section + .wallpaper-section {
  padding-top: 4px;
}

</style>
