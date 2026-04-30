<script setup lang="ts">
import WallpaperSection from './components/WallpaperSection.vue'
import { useWallpaperSettings } from './hooks/useWallpaperSettings'

const controller = useWallpaperSettings()
const { settingsStore } = controller

const primaryColorPresets = [
  '#2563eb',
  '#0891b2',
  '#059669',
  '#7c3aed',
  '#db2777',
  '#ea580c',
]
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
        <NFormItem label="主题色">
          <div class="flex flex-wrap items-center gap-[12px]">
            <NColorPicker
              class="w-[180px]"
              :value="settingsStore.primaryColor"
              :show-alpha="false"
              :modes="['hex']"
              @update:value="settingsStore.setPrimaryColor"
            />
            <div class="flex items-center gap-[8px]">
              <button
                v-for="color in primaryColorPresets"
                :key="color"
                type="button"
                class="h-[28px] w-[28px] rounded-full border border-[rgba(148,163,184,0.28)] p-0 transition-[transform,box-shadow] duration-[160ms] ease-in-out hover:scale-[1.08] cursor-pointer"
                :class="settingsStore.primaryColor === color ? 'shadow-[0_0_0_3px_var(--app-primary-soft)]' : ''"
                :style="{ backgroundColor: color }"
                :aria-label="`设置主题色 ${color}`"
                @click="settingsStore.setPrimaryColor(color)"
              />
            </div>
            <NButton secondary @click="settingsStore.resetPrimaryColor">恢复默认</NButton>
          </div>
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
